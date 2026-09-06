# frozen_string_literal: true

RSpec.describe Adapter::Loader::File::SpecLoader do
  subject(:loader) { described_class.new }

  it "читает описание в YAML" do
    expect(loader.read(example_spec("novapay"))).to include(openapi: "3.0.3")
  end

  it "читает описание в JSON" do
    path = File.join(Dir.tmpdir, "spec.json")
    File.write(path, '{"openapi":"3.1.0"}')
    expect(loader.read(path)).to eq(openapi: "3.1.0")
  ensure
    File.unlink(path)
  end

  describe "когда файла нет" do
    it "говорит об этом словами" do
      expect { loader.read("нет.yaml") }.to raise_error(ArgumentError, /не найдено/)
    end
  end

  describe "когда файл не разбирается" do
    it "называет причину" do
      path = File.join(Dir.tmpdir, "broken.yaml")
      File.write(path, "\tнеправильный отступ: [")
      expect { loader.read(path) }.to raise_error(ArgumentError, /не разобрать YAML/)
    ensure
      File.unlink(path)
    end
  end

  describe "когда локаль процесса не UTF-8" do
    let(:path) { File.join(Dir.tmpdir, "not_ascii.yaml") }

    around do |example|
      File.write(path, "title: провайдер с кириллицей\n", encoding: "UTF-8")
      original = Encoding.default_external
      Encoding.default_external = Encoding::US_ASCII
      example.run
    ensure
      Encoding.default_external = original
      File.unlink(path)
    end

    it "всё равно читает не-ASCII содержимое файла" do
      expect(loader.read(path)[:title]).to eq("провайдер с кириллицей")
    end
  end
end
