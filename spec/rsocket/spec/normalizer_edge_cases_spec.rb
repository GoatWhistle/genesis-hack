# frozen_string_literal: true

require "tempfile"

require "spec_helper"

RSpec.describe Rsocket::Spec::Normalizer do
  def normalize_yaml(contents)
    Tempfile.create(["unusual_provider", ".yaml"]) do |file|
      file.write(contents)
      file.flush
      return described_class.normalize(Rsocket::Spec::Loader.load(file.path))
    end
  end

  def normalization_error(contents)
    normalize_yaml(contents)
    raise "Ожидали, что раскладка упадёт"
  rescue Rsocket::Error => e
    e
  end

  def unknown_auth_summary(result)
    scheme = result.security_schemes.first
    note = result.notes.find { |item| item.where.start_with?("components.securitySchemes") }
    [scheme.kind, scheme.description, note.level, note.where, note.message]
  end

  def alternative_auth_summary(result)
    schemes = result.security_schemes.map { |scheme| [scheme.id, scheme.kind] }
    [schemes, result.operations.first.security]
  end

  def expected_coverage_notes
    [
      coverage_note("Для операции не описано ни одного примера; мок соберёт ответ по схеме"),
      coverage_note(
        "Для операции не описаны ответы с ошибками; " \
        "обработку отказов нужно проверить вручную"
      )
    ]
  end

  def coverage_note(message)
    { level: :needs_confirmation, where: "paths./transfers.post.responses", message: message }
  end

  def no_operations_yaml
    <<~YAML
      openapi: 3.1.0
      info: { title: No operations, version: 1.0.0 }
      paths:
        /transfers/{id}:
          parameters:
            - in: path
              name: id
              required: true
              schema: { type: string }
    YAML
  end

  def unknown_auth_yaml
    <<~YAML
      openapi: 3.1.0
      info: { title: Custom auth, version: 1.0.0 }
      paths:
        /transfers:
          get:
            responses:
              '200': { description: ok }
      components:
        securitySchemes:
          SignedRequest:
            type: customSignature
            description: Provider-specific signing
      security:
        - SignedRequest: []
    YAML
  end

  def no_examples_or_errors_yaml
    <<~YAML
      openapi: 3.0.3
      info: { title: Sparse API, version: 1.0.0 }
      paths:
        /transfers:
          post:
            requestBody:
              content:
                application/json:
                  schema:
                    type: object
                    properties:
                      amount: { type: number, minimum: 0.01 }
            responses:
              '200':
                description: accepted
                content:
                  application/json:
                    schema:
                      type: object
                      properties:
                        id: { type: string }
    YAML
  end

  def query_only_input_yaml
    <<~YAML
      openapi: 3.0.3
      info: { title: Query input, version: 1.0.0 }
      paths:
        /transfers:
          post:
            parameters:
              - in: query
                name: amount
                required: true
                schema: { type: number, minimum: 0.01 }
              - in: query
                name: recipient
                required: true
                schema: { type: string }
            responses:
              '202': { description: queued }
    YAML
  end

  # Описание, где требование авторизации есть только словами: раздела
  # securitySchemes нет, зато в тексте операции сказано про заголовок с ключом.
  def prose_only_auth_yaml
    <<~YAML
      openapi: 3.0.1
      info: { title: Prose auth, version: "1.4" }
      paths:
        /payment-orders:
          post:
            description: Запрос выполняется с заголовком X-Access-Key, значение — ключ доступа.
            responses:
              '201': { description: accepted }
    YAML
  end

  def undeclared_auth_note(result)
    result.notes.find { |note| note.where == "components.securitySchemes" }
  end

  def alternative_auth_yaml
    <<~YAML
      openapi: 3.1.0
      info: { title: Alternative auth, version: 1.0.0 }
      paths:
        /transfers:
          get:
            responses:
              '200': { description: ok }
      components:
        securitySchemes:
          HeaderKey:
            type: apiKey
            in: header
            name: X-Access-Key
          BearerToken:
            type: http
            scheme: bearer
      security:
        - HeaderKey: []
        - BearerToken: []
    YAML
  end

  it "замечает раздел paths с параметрами, но без методов" do
    error = normalization_error(no_operations_yaml)
    expect([error.class, error.where, error.message.lines.size])
      .to eq([Rsocket::SpecError, "paths", 1])
  end

  it "сохраняет незнакомый способ авторизации и объясняет его в отчёте" do
    result = normalize_yaml(unknown_auth_yaml)
    expect(unknown_auth_summary(result))
      .to eq([:unknown, "Provider-specific signing", :needs_confirmation,
              "components.securitySchemes.SignedRequest",
              "Способ авторизации не распознан и требует ручной проверки"])
  end

  it "принимает операцию без примеров и без описанных ошибок" do
    operation = normalize_yaml(no_examples_or_errors_yaml).operations.first
    actual = [operation.request_examples, operation.responses.keys,
              operation.responses.fetch(200).examples]
    expect(actual).to eq([{}, [200], {}])
  end

  it "называет обе нехватки — примеры и ответы с ошибками" do
    notes = normalize_yaml(no_examples_or_errors_yaml).notes
    operation_notes = notes.select { |note| note.where.start_with?("paths.") }

    expect(operation_notes.map(&:to_h)).to match_array(expected_coverage_notes)
  end

  it "не путает параметры в строке запроса с отсутствующим телом" do
    operation = normalize_yaml(query_only_input_yaml).operations.first
    actual = [operation.query_params.map(&:name), operation.query_params.map(&:required),
              operation.request_fields]
    expect(actual).to eq([%w[amount recipient], [true, true], []])
  end

  it "не выдаёт описание без схем авторизации за открытый API" do
    result = normalize_yaml(prose_only_auth_yaml)
    note = undeclared_auth_note(result)

    expect([result.security_schemes, note.level]).to eq([[], :needs_confirmation])
  end

  it "сохраняет текст операции, в котором требование авторизации записано словами" do
    operation = normalize_yaml(prose_only_auth_yaml).operations.first

    expect(operation.description).to include("X-Access-Key")
  end

  it "сохраняет оба способа авторизации на выбор" do
    result = normalize_yaml(alternative_auth_yaml)
    expect(alternative_auth_summary(result)).to eq(
      [[["HeaderKey", :api_key], ["BearerToken", :bearer]], %w[HeaderKey BearerToken]]
    )
  end
end
