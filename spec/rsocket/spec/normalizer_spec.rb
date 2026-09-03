# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Spec::Normalizer do
  subject(:ir_spec) { described_class.normalize(loader_result) }

  let(:loader_result) { Rsocket::Spec::Loader.load(spec_path) }
  let(:spec_path) { File.join(Rsocket.root, "examples", "novapay", "provider_api.yaml") }
  let(:create_operation) { ir_spec.operations.find { |item| item.operation_id == "createPayout" } }
  let(:webhook_operation) do
    ir_spec.operations.find { |item| item.operation_id == "payoutWebhook" }
  end

  it "normalizes every operation" do
    expect(ir_spec.operations.size).to eq(5)
  end

  it "keeps operation identities" do
    identities = ir_spec.operations.map { |item| [item.http_method, item.path] }

    expect(identities).to include([:post, "/payouts"], [:get, "/balance"])
  end

  it "detects server environments" do
    expect(ir_spec.servers.map(&:env)).to eq(%i[sandbox production])
  end

  it "normalizes API-key authentication" do
    scheme = ir_spec.security_schemes.first

    expect(scheme.to_h).to include(kind: :api_key, location: :header, name: "X-API-Key")
  end

  it "inherits operation security" do
    expect(create_operation.security).to eq(["ApiKeyAuth"])
  end

  it "preserves explicitly open operations" do
    expect(webhook_operation.security).to be_empty
  end

  it "normalizes request fields" do
    expect(create_operation.request_fields.map(&:name)).to eq(
      %w[amount currency external_id recipient]
    )
  end

  it "builds full paths for nested fields" do
    recipient = create_operation.request_fields.find { |field| field.name == "recipient" }

    expect(recipient.children.map(&:path)).to include("recipient.phone", "recipient.bank_code")
  end

  it "takes required from the containing object" do
    recipient = create_operation.request_fields.find { |field| field.name == "recipient" }
    required = recipient.children.select(&:required).map(&:name)

    expect(required).to contain_exactly("type", "phone")
  end

  it "reads named request examples" do
    expect(create_operation.request_examples).to have_key("sbp_payout")
  end

  it "reads singular response examples" do
    expect(create_operation.responses.fetch(201).examples).to have_key("default")
  end

  it "normalizes response headers" do
    expect(create_operation.responses.fetch(429).headers.map(&:name)).to eq(["Retry-After"])
  end

  it "keeps source schemas unresolved" do
    source_recipient = loader_result.raw_document.dig("components", "schemas", "Recipient")

    expect(ir_spec.raw_schemas.fetch("Recipient")).to eq(source_recipient)
  end

  context "when no HTTP operations are described" do
    let(:loader_result) do
      document = { "openapi" => "3.1.0", "info" => {}, "paths" => {} }
      Rsocket::Spec::Loader::Result.new(document:, raw_document: document, notes: [])
    end

    it "returns a human-readable error" do
      expect { ir_spec }.to raise_error(Rsocket::SpecError, /не содержит.*операц/i)
    end
  end

  context "with the decimal bearer-token example" do
    let(:spec_path) { File.join(Rsocket.root, "examples", "swiftpay", "provider_api.yaml") }

    it "normalizes every operation" do
      expect(ir_spec.operations.size).to eq(3)
    end

    it "normalizes bearer authentication" do
      expect(ir_spec.security_schemes.map(&:kind)).to eq([:bearer])
    end

    it "keeps decimal amounts" do
      amount = ir_spec.operations.first.request_fields.find { |field| field.name == "amount" }

      expect(amount.to_h).to include(type: "number", example: 149.90)
    end

    it "normalizes query parameters" do
      status = ir_spec.operations.find { |item| item.http_method == :get }

      expect(status.query_params.map(&:name)).to contain_exactly("include", "locale")
    end
  end

  context "with the OpenAPI 3.1 envelope example" do
    let(:spec_path) { File.join(Rsocket.root, "examples", "kassabox", "provider_api.yaml") }

    it "normalizes every operation" do
      expect(ir_spec.operations.size).to eq(4)
    end

    it "normalizes alternative authentication schemes" do
      expect(ir_spec.security_schemes.map(&:kind)).to contain_exactly(:api_key, :basic)
    end

    it "keeps response envelopes" do
      responses = ir_spec.operations.first.responses.values
      response = responses.find { |item| item.code.between?(200, 299) }

      expect(response.fields.map(&:name)).to contain_exactly("data", "meta")
    end

    it "keeps the refund operation" do
      expect(ir_spec.operations.map(&:operation_id)).to include("issueRefund")
    end
  end

  context "with an unknown authentication type" do
    let(:loader_result) do
      document = unknown_security_document
      Rsocket::Spec::Loader::Result.new(document:, raw_document: document, notes: [])
    end

    it "keeps the scheme as unknown" do
      expect(ir_spec.security_schemes.first.kind).to eq(:unknown)
    end

    it "records the ambiguity" do
      expect(ir_spec.notes.map(&:level)).to include(:needs_confirmation)
    end

    def unknown_security_document
      {
        "openapi" => "3.1.0", "info" => {}, "paths" => { "/items" => read_operation },
        "components" => { "securitySchemes" => { "Custom" => { "type" => "mutualTLS" } } }
      }
    end

    def read_operation
      { "get" => { "responses" => { "200" => { "description" => "ok" } } } }
    end
  end

  context "with a singular example on a schema" do
    let(:loader_result) do
      document = schema_example_document
      Rsocket::Spec::Loader::Result.new(document:, raw_document: document, notes: [])
    end

    it "keeps the example" do
      expect(ir_spec.operations.first.request_examples).to eq("default" => { "value" => 7 })
    end

    def schema_example_document
      request_schema = { "type" => "object", "example" => { "value" => 7 } }
      request = { "content" => { "application/json" => { "schema" => request_schema } } }
      operation = { "requestBody" => request, "responses" => { "200" => {} } }
      { "openapi" => "3.1.0", "info" => {}, "paths" => { "/items" => { "post" => operation } } }
    end
  end
end
