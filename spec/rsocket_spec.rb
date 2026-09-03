# frozen_string_literal: true

require "yaml"

# Смоук-тест сборки. Проверяет не логику, а то, что окружение поднялось:
# гем грузится, версия объявлена, корень репозитория находится оттуда,
# откуда бы команду ни запустили.
RSpec.describe Rsocket do
  def load_example(name)
    path = File.join(Rsocket.root, "examples", name, "provider_api.yaml")
    Psych.safe_load_file(path, aliases: true)
  end

  def operations(document)
    document.fetch("paths").values.flat_map do |path_item|
      path_item.slice("get", "post", "put", "patch", "delete").values
    end
  end

  def success_response_refs(document)
    responses = operations(document).flat_map { |operation| operation.fetch("responses").to_a }
    responses.select { |code, _response| code.start_with?("2") }
             .map do |_code, response|
               response.dig("content", "application/json", "schema", "$ref")
             end
  end

  describe "VERSION" do
    subject(:version) { described_class::VERSION }

    it { is_expected.to be_a(String) }

    it "выглядит как семвер" do
      expect(version).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe ".root" do
    subject(:root) { described_class.root }

    it "указывает на существующий каталог" do
      expect(File.directory?(root)).to be true
    end

    it "содержит точку входа lib/rsocket.rb" do
      expect(File.file?(File.join(root, "lib", "rsocket.rb"))).to be true
    end

    it "возвращает абсолютный путь" do
      expect(root).to eq(File.expand_path(root))
    end
  end

  describe "provider neutrality" do
    it "does not hardcode example-provider vocabulary in library code" do
      files = Dir[File.join(described_class.root, "lib", "**", "*.rb")]
      checked = files.grep_v(%r{/rsocket/(dictionaries|templates)/})
      forbidden = /novapay|swiftpay|kassabox|payouts|sbp/i
      violations = checked.select { |path| File.read(path).match?(forbidden) }

      expect(violations).to be_empty
    end
  end

  describe "SwiftPay example" do
    subject(:document) { load_example("swiftpay") }

    it "declares bearer authentication" do
      scheme = document.dig("components", "securitySchemes", "BearerAuth")

      expect(scheme).to include("type" => "http", "scheme" => "bearer")
    end

    it "uses bearer authentication globally" do
      expect(document.fetch("security")).to eq([{ "BearerAuth" => [] }])
    end

    it "models amounts as decimal numbers" do
      amount = document.dig("components", "schemas", "TransferRequest", "properties", "amount")

      expect(amount).to include("type" => "number", "multipleOf" => 0.01)
    end

    it "provides a decimal amount example" do
      amount = document.dig("components", "schemas", "TransferRequest", "properties", "amount")

      expect(amount.fetch("example")).to eq(149.9)
    end

    it "uses the provider's status vocabulary" do
      status = document.dig("components", "schemas", "Transfer", "properties", "status")

      expect(status.fetch("enum")).to eq(%w[new sent paid declined])
    end

    it "has query parameters on status polling" do
      parameters = document.dig("paths", "/transfers/{transfer_id}", "get", "parameters")

      expect(parameters).to include(include("in" => "query", "name" => "include"))
    end

    it "has no notification path" do
      expect(document.fetch("paths").keys.grep(/webhook|notification/i)).to be_empty
    end

    it "has no notification callback" do
      expect(operations(document).flat_map(&:keys)).not_to include("callbacks")
    end
  end

  describe "KassaBox example" do
    subject(:document) { load_example("kassabox") }

    it "uses OpenAPI 3.1" do
      expect(document.fetch("openapi")).to start_with("3.1.")
    end

    it "declares two authentication schemes" do
      schemes = document.dig("components", "securitySchemes").keys

      expect(schemes).to contain_exactly("MerchantKey", "BasicAuth")
    end

    it "allows either authentication scheme" do
      choices = [{ "MerchantKey" => [] }, { "BasicAuth" => [] }]

      expect(document.fetch("security")).to match_array(choices)
    end

    it "keeps deliberately opaque operation identifiers" do
      ids = operations(document).filter_map { |operation| operation["operationId"] }

      expect(ids).to include("makeTransfer", "transferInfo", "abortTransfer")
    end

    it "uses envelope schemas for every successful response" do
      expect(success_response_refs(document)).to all(match(/Envelope\z/))
    end

    %w[TransferEnvelope RefundEnvelope].each do |name|
      it "wraps #{name} in data and meta" do
        properties = document.dig("components", "schemas", name, "properties")

        expect(properties.keys).to contain_exactly("data", "meta")
      end
    end

    it "includes refunds" do
      refund = document.dig("paths", "/v1/refunds", "post")

      expect(refund.fetch("operationId")).to eq("issueRefund")
    end

    it "leaves refund errors undocumented" do
      refund = document.dig("paths", "/v1/refunds", "post")

      expect(refund.fetch("responses").keys).to eq(["201"])
    end

    it "leaves transfer status errors undocumented" do
      responses = document.dig("paths", "/v1/transfers/{transferNo}", "get", "responses")

      expect(responses.keys).to eq(["200"])
    end
  end
end
