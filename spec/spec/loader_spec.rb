# frozen_string_literal: true

require "tempfile"

require "rsocket/spec/loader"

# Разбор описания живёт в spec/spec/, а сам класс — внутри Rsocket. Псевдоним
# нужен только для того, чтобы RuboCop не спорил о раскладке каталогов: имя
# каталога здесь наше, а не производное от неймспейса.
module Spec
  Loader = Rsocket::Spec::Loader
end

RSpec.describe Spec::Loader do
  def with_spec(contents)
    Tempfile.create(["provider_api", ".yaml"]) do |file|
      file.write(contents)
      file.flush
      yield file.path
    end
  end

  def load_yaml(contents, **options)
    with_spec(contents) { |path| described_class.load(path, **options) }
  end

  def note_values(note)
    [note.level, note.where, note.message]
  end

  def reference_versions(result)
    keys = %w[paths /items post requestBody content application/json schema]
    [result.document.dig(*keys), result.raw_document.dig(*keys)]
  end

  def expected_reference_versions
    [{ "type" => "object", "properties" => { "id" => { "type" => "string" } } },
     { "$ref" => "#/components/schemas/Item" }]
  end

  def aliases_yaml
    <<~YAML
      openapi: 3.0.3
      common: &common
        type: string
      paths:
        /items:
          parameters:
            - *common
    YAML
  end

  def local_reference_yaml
    <<~YAML
      openapi: 3.0.3
      paths:
        /items:
          post:
            requestBody:
              content:
                application/json:
                  schema:
                    $ref: '#/components/schemas/Item'
      components:
        schemas:
          Item:
            type: object
            properties:
              id:
                type: string
    YAML
  end

  def escaped_pointer_yaml
    <<~YAML
      openapi: 3.1.0
      paths:
        /items:
          get:
            responses:
              '200':
                $ref: '#/components/responses/a~1b~0c'
      components:
        responses:
          a/b~c:
            description: ok
    YAML
  end

  def all_of_yaml
    <<~YAML
      openapi: 3.0.3
      paths: {}
      components:
        schemas:
          Combined:
            allOf:
              - type: object
                required: [id]
                properties:
                  id: { type: string }
              - required: [amount]
                properties:
                  amount: { type: number }
    YAML
  end

  def one_of_yaml
    <<~YAML
      openapi: 3.1.0
      paths: {}
      components:
        schemas:
          Value:
            oneOf:
              - { type: string }
              - { type: integer }
    YAML
  end

  def any_of_yaml
    <<~YAML
      openapi: 3.0.3
      paths: {}
      components:
        schemas:
          Value:
            anyOf:
              - { type: boolean }
              - { type: string }
    YAML
  end

  def external_reference_yaml
    <<~YAML
      openapi: 3.0.3
      paths:
        /items:
          get:
            responses:
              '200':
                $ref: './common.yaml#/responses/Success'
    YAML
  end

  def missing_reference_yaml
    <<~YAML
      openapi: 3.0.3
      paths:
        /items:
          get:
            responses:
              '200':
                $ref: '#/components/responses/Missing'
      components:
        responses: {}
    YAML
  end

  def circular_reference_yaml
    <<~YAML
      openapi: 3.0.3
      paths: {}
      components:
        schemas:
          Left:
            $ref: '#/components/schemas/Right'
          Right:
            $ref: '#/components/schemas/Left'
    YAML
  end

  def deep_reference_yaml
    <<~YAML
      openapi: 3.0.3
      paths:
        /items:
          get:
            responses:
              '200':
                $ref: '#/components/responses/First'
      components:
        responses:
          First:
            $ref: '#/components/responses/Second'
          Second:
            description: ok
    YAML
  end

  it "читает описания OpenAPI 3.0 и 3.1" do
    %w[3.0.3 3.1.0].each do |version|
      result = load_yaml("openapi: #{version}\npaths: {}\n")
      expect(result.document).to include("openapi" => version, "paths" => {})
    end
  end

  it "разворачивает безопасные псевдонимы YAML" do
    result = load_yaml(aliases_yaml)
    expect(result.document.dig("paths", "/items", "parameters", 0)).to eq("type" => "string")
  end

  it "раскрывает локальные ссылки, не трогая исходный документ" do
    result = load_yaml(local_reference_yaml)
    expect(reference_versions(result)).to eq(expected_reference_versions)
  end

  it "понимает экранирование в локальных ссылках" do
    result = load_yaml(escaped_pointer_yaml)
    response = result.document.dig("paths", "/items", "get", "responses", "200")
    expect(response).to eq("description" => "ok")
  end

  it "сливает поля и обязательность из всех веток allOf" do
    schema = load_yaml(all_of_yaml).document.dig("components", "schemas", "Combined")
    expected = { "type" => "object", "required" => %w[id amount],
                 "properties" => { "id" => { "type" => "string" },
                                   "amount" => { "type" => "number" } } }
    expect(schema).to eq(expected)
  end

  it "берёт первую ветку oneOf и оставляет пометку на проверку" do
    result = load_yaml(one_of_yaml)
    actual = [result.document.dig("components", "schemas", "Value", "type"),
              note_values(result.notes.first)]
    expect(actual).to eq(["string", [:needs_confirmation, "components.schemas.Value.oneOf",
                                     "oneOf содержит несколько вариантов; выбрана первая ветка"]])
  end

  it "берёт первую ветку anyOf и оставляет пометку на проверку" do
    result = load_yaml(any_of_yaml)
    actual = [result.document.dig("components", "schemas", "Value", "type"),
              note_values(result.notes.first).first(2)]
    expect(actual).to eq(["boolean", [:needs_confirmation, "components.schemas.Value.anyOf"]])
  end

  it "оставляет внешнюю ссылку как есть и пишет о ней в отчёт" do
    result = load_yaml(external_reference_yaml)
    response = result.document.dig("paths", "/items", "get", "responses", "200")
    actual = [response, note_values(result.notes.first).first(2)]
    expect(actual).to eq([{ "$ref" => "./common.yaml#/responses/Success" },
                          [:unsupported, "paths./items.get.responses.200.$ref"]])
  end

  it "внятно объясняет ссылку, ведущую в никуда" do
    pattern = %r{отсутствующий узел.*#/components/responses/Missing.*paths\./items\.get}
    expect { load_yaml(missing_reference_yaml) }.to raise_error(Rsocket::ReferenceError, pattern)
  end

  it "не зацикливается на кольцевых ссылках" do
    expect { load_yaml(circular_reference_yaml) }
      .to raise_error(Rsocket::ReferenceError, /кольцевая локальная ссылка/)
  end

  it "обрывает слишком длинную цепочку ссылок" do
    expect { load_yaml(deep_reference_yaml, max_reference_depth: 1) }
      .to raise_error(Rsocket::ReferenceError, /максимальная глубина локальных ссылок \(1\)/)
  end

  it "показывает строку, на которой сломался YAML" do
    expect { load_yaml("openapi: 3.0.3\npaths:\n  broken: [\n") }
      .to raise_error(Rsocket::SpecError, /Не удалось разобрать YAML.*строка 4/)
  end

  it "отказывается работать с пустым файлом" do
    expect { load_yaml(" \n\t") }.to raise_error(Rsocket::SpecError, /Описание API пустое/)
  end

  it "считает пустым документ из одних комментариев" do
    expect { load_yaml("---\n# only a comment\n") }
      .to raise_error(Rsocket::SpecError, /Описание API пустое/)
  end

  it "отказывается работать без раздела paths" do
    expect { load_yaml("openapi: 3.0.3\ninfo: {}\n") }
      .to raise_error(Rsocket::SpecError, /нет обязательного раздела paths/)
  end

  it "сообщает, что файла нет" do
    path = File.join(Dir.tmpdir, "rsocket-missing-#{Process.pid}.yaml")
    expect { described_class.load(path) }
      .to raise_error(Rsocket::SpecError, /файл не найден.*#{Regexp.escape(path)}/)
  end

  it "сообщает, что файл недоступен на чтение" do
    allow(File).to receive(:read).and_raise(Errno::EACCES, "Permission denied")
    expect { described_class.load("locked.yaml") }
      .to raise_error(Rsocket::SpecError, /нет прав на чтение.*locked\.yaml/)
  end
end
