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

  it "раскладывает все операции" do
    expect(ir_spec.operations.size).to eq(5)
  end

  it "запоминает метод и путь каждой операции" do
    identities = ir_spec.operations.map { |item| [item.http_method, item.path] }

    expect(identities).to include([:post, "/payouts"], [:get, "/balance"])
  end

  it "различает песочницу и боевой сервер" do
    expect(ir_spec.servers.map(&:env)).to eq(%i[sandbox production])
  end

  it "разбирает авторизацию по ключу в заголовке" do
    scheme = ir_spec.security_schemes.first

    expect(scheme.to_h).to include(kind: :api_key, location: :header, name: "X-API-Key")
  end

  it "наследует авторизацию из корня описания" do
    expect(create_operation.security).to eq(["ApiKeyAuth"])
  end

  it "оставляет открытой операцию, которой авторизация не нужна" do
    expect(webhook_operation.security).to be_empty
  end

  it "раскладывает поля запроса" do
    expect(create_operation.request_fields.map(&:name)).to eq(
      %w[amount currency external_id recipient]
    )
  end

  it "собирает полный путь до вложенного поля" do
    recipient = create_operation.request_fields.find { |field| field.name == "recipient" }

    expect(recipient.children.map(&:path)).to include("recipient.phone", "recipient.bank_code")
  end

  it "берёт обязательность из объекта, которому поле принадлежит" do
    recipient = create_operation.request_fields.find { |field| field.name == "recipient" }
    required = recipient.children.select(&:required).map(&:name)

    expect(required).to contain_exactly("type", "phone")
  end

  it "читает именованные примеры запроса" do
    expect(create_operation.request_examples).to have_key("sbp_payout")
  end

  it "читает одиночный пример ответа" do
    expect(create_operation.responses.fetch(201).examples).to have_key("default")
  end

  it "раскладывает заголовки ответа" do
    expect(create_operation.responses.fetch(429).headers.map(&:name)).to eq(["Retry-After"])
  end

  it "хранит исходные схемы с нераскрытыми ссылками" do
    source_recipient = loader_result.raw_document.dig("components", "schemas", "Recipient")

    expect(ir_spec.raw_schemas.fetch("Recipient")).to eq(source_recipient)
  end

  context "когда HTTP-операций в описании нет" do
    let(:loader_result) do
      document = { "openapi" => "3.1.0", "info" => {}, "paths" => {} }
      Rsocket::Spec::Loader::Result.new(document:, raw_document: document, notes: [])
    end

    it "объясняет это человеческим сообщением" do
      expect { ir_spec }.to raise_error(Rsocket::SpecError, /не содержит.*операц/i)
    end
  end

  context "на примере с дробными суммами и токеном" do
    let(:spec_path) { File.join(Rsocket.root, "examples", "swiftpay", "provider_api.yaml") }

    it "раскладывает все операции" do
      expect(ir_spec.operations.size).to eq(3)
    end

    it "разбирает авторизацию по токену" do
      expect(ir_spec.security_schemes.map(&:kind)).to eq([:bearer])
    end

    it "не портит дробную сумму" do
      amount = ir_spec.operations.first.request_fields.find { |field| field.name == "amount" }

      expect(amount.to_h).to include(type: "number", example: 149.90)
    end

    it "раскладывает параметры строки запроса" do
      status = ir_spec.operations.find { |item| item.http_method == :get }

      expect(status.query_params.map(&:name)).to contain_exactly("include", "locale")
    end
  end

  context "на примере OpenAPI 3.1 с обёрткой ответа" do
    let(:spec_path) { File.join(Rsocket.root, "examples", "kassabox", "provider_api.yaml") }

    it "раскладывает все операции" do
      expect(ir_spec.operations.size).to eq(4)
    end

    it "разбирает оба способа авторизации на выбор" do
      expect(ir_spec.security_schemes.map(&:kind)).to contain_exactly(:api_key, :basic)
    end

    it "сохраняет обёртку ответа" do
      responses = ir_spec.operations.first.responses.values
      response = responses.find { |item| item.code.between?(200, 299) }

      expect(response.fields.map(&:name)).to contain_exactly("data", "meta")
    end

    it "не теряет операцию возврата" do
      expect(ir_spec.operations.map(&:operation_id)).to include("issueRefund")
    end
  end

  context "с незнакомым способом авторизации" do
    let(:loader_result) do
      document = unknown_security_document
      Rsocket::Spec::Loader::Result.new(document:, raw_document: document, notes: [])
    end

    it "оставляет способ нераспознанным" do
      expect(ir_spec.security_schemes.first.kind).to eq(:unknown)
    end

    it "пишет о нём в отчёт" do
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

  context "с одиночным примером прямо на схеме" do
    let(:loader_result) do
      document = schema_example_document
      Rsocket::Spec::Loader::Result.new(document:, raw_document: document, notes: [])
    end

    it "не теряет этот пример" do
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
