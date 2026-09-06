# frozen_string_literal: true

require "webmock/rspec"

# Независимые части OpenAPI нужны контекстам для проверки разных форм ответа и маршрута.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "ответы и маршруты сгенерированного адаптера" do
  let(:id_schema) { { type: "string" } }
  let(:status_schema) { { type: "string", enum: %w[pending completed cancelled] } }
  let(:create_schema) { { type: "object", properties: { id: id_schema } } }
  let(:read_schema) { { type: "object", properties: { status: status_schema } } }
  let(:collection) { "/payouts" }
  let(:item) { "#{collection}/{code}" }
  let(:parameters) { [] }
  let(:document) do
    { openapi: "3.0.0", servers: [{ url: "https://provider.test" }], paths: {
      collection => { parameters: parameters, post: {
        operationId: "createPayout", responses: response(create_schema)
      } },
      item => { parameters: item_parameters, get: {
        operationId: "getPayout", responses: response(read_schema)
      } },
      "#{item}/cancel" => { parameters: item_parameters, post: {
        operationId: "cancelPayout", responses: response(read_schema)
      } }
    } }
  end
  let(:result) do
    Rsocket.builder(rules: rules, spec_source: Adapter::Loader::Text::SpecReader.new)
           .call(reference: document.to_json, provider: "regression")
  end
  let(:namespace) do
    Module.new.tap do |space|
      space.module_eval(File.read("app/config/rules/contracts/space_payments/probe.rb"))
      space.module_eval(result.source)
    end
  end
  let(:service) { namespace.const_get(:Provider).const_get(:RegressionService).new }
  let(:payment) do
    namespace.const_get(:Provider).const_get(:Operation).new(
      id: "merchant-1", provider_operation_id: "payout-1", payout_requisite: {}
    )
  end

  def item_parameters
    parameters + [parameter(item.scan(/\{([^}]+)\}/).last.first)]
  end

  def location_response(schema = { type: "string", format: "uri" })
    document[:paths][collection][:post][:responses] = {
      "201" => { description: "created", headers: { Location: { schema: schema } } }
    }
  end

  def response(schema)
    { "200" => { description: "ok", content: { "application/json": { schema: schema } } } }
  end

  def parameter(name, schema = { type: "string" })
    { name: name, in: "path", required: true, schema: schema }
  end

  def reply(method, path, body, headers = {})
    stub_request(method, "https://provider.test#{path}")
      .to_return(status: 200, body: body.to_json, headers: headers)
  end

  it "подставляет ID в параметр code по положению ресурса" do
    reply(:get, "/payouts/payout-1", status: "completed")
    expect(service.fetch_status(payment)).to eq("approved")
  end

  it "кодирует URL-идентификатор целиком как один сегмент пути" do
    payment.provider_operation_id = "https://wallet.test/outgoing/42?x=1#part"
    reply(:get, "/payouts/https%3A%2F%2Fwallet.test%2Foutgoing%2F42%3Fx%3D1%23part",
          status: "completed")
    expect(service.fetch_status(payment)).to eq("approved")
  end

  it "не обращается к провайдеру при пустом ID" do
    payment.provider_operation_id = nil
    expect(service.fetch_status(payment)).to have_attributes(ok: false,
                                                             code: "provider.missing_parameter")
  end

  it "возвращает отказ, если успешный ответ создания не содержит ID" do
    reply(:post, "/payouts", {})
    expect(service.create_request(payment)).to have_attributes(
      ok: false, code: "provider.missing_operation_id"
    )
  end

  context "с идентификатором пачки в конверте" do
    let(:item) { "/payouts/{payout_batch_id}" }
    let(:create_schema) do
      { type: "object", properties: { batch_header: {
        type: "object", properties: { payout_batch_id: id_schema }
      } } }
    end

    it "связывает имя идентификатора из маршрута со схемой создания" do
      reply(:post, "/payouts", batch_header: { payout_batch_id: "batch-1" })
      service.create_request(payment)
      expect(payment.provider_operation_id).to eq("batch-1")
    end
  end

  context "с массивом в ответе статуса" do
    let(:item) { "/payouts/{id}" }
    let(:read_schema) do
      { type: "object", properties: { Data: {
        type: "object", properties: { Payment: { type: "array", items: {
          type: "object", properties: { status: status_schema }
        } } }
      } } }
    end

    it "читает статус единственного элемента" do
      reply(:get, "/payouts/payout-1", Data: { Payment: [{ status: "completed" }] })
      expect(service.fetch_status(payment)).to eq("approved")
    end

    it "не выбирает произвольно первый платёж из нескольких" do
      reply(:get, "/payouts/payout-1",
            Data: { Payment: [{ status: "completed" }, { status: "pending" }] })
      expect(service.fetch_status(payment)).to eq("in_progress")
    end

    it "не падает при строке вместо массива" do
      reply(:get, "/payouts/payout-1", Data: { Payment: "unexpected" })
      expect(service.fetch_status(payment)).to eq("in_progress")
    end
  end

  context "с отличающимся ответом отмены" do
    let(:item) { "/payouts/{id}" }

    it "использует схему ответа именно отмены" do
      schema = { type: "object",
                 properties: { result: { type: "object", properties: { state: status_schema } } } }
      document[:paths]["#{item}/cancel"][:post][:responses] = response(schema)
      reply(:post, "/payouts/payout-1/cancel", result: { state: "cancelled" })
      expect(service.cancel_request(payment)).to eq("rejected")
    end
  end

  context "с параметрами выбора продукта" do
    let(:collection) { "/{service}/{product}" }
    let(:parameters) { [parameter("service"), parameter("product")] }

    it "берёт выбор продукта из реквизитов, а не из ID платежа" do
      payment.payout_requisite = { "service" => "payments", "product" => "credit-transfer" }
      reply(:get, "/payments/credit-transfer/payout-1", status: "completed")
      expect(service.fetch_status(payment)).to eq("approved")
    end
  end

  context "с единственным значением параметра" do
    let(:collection) { "/{service}/payouts" }
    let(:parameters) { [parameter("service", type: "string", enum: ["payments"])] }

    it "использует единственное допустимое значение без ручного заполнения" do
      reply(:get, "/payments/payouts/payout-1", status: "completed")
      expect(service.fetch_status(payment)).to eq("approved")
    end
  end

  context "с ID в заголовке Location" do
    let(:item) { "/payouts/{id}" }

    it "извлекает ID созданного ресурса из объявленного заголовка" do
      location_response
      reply(:post, "/payouts", {}, "Location" => "https://provider.test/payouts/new-id")
      service.create_request(payment)
      expect(payment.provider_operation_id).to eq("new-id")
    end
  end

  context "с ID родительского счёта" do
    let(:collection) { "/accounts/{account_id}/payouts" }
    let(:parameters) { [parameter("account_id")] }

    it "не подменяет счёт идентификатором выплаты" do
      payment.payout_requisite = { "account_id" => "account-7" }
      reply(:get, "/accounts/account-7/payouts/payout-1", status: "completed")
      expect(service.fetch_status(payment)).to eq("approved")
    end

    it "отказывает без явно заданного счёта до отправки запроса" do
      expect(service.fetch_status(payment)).to have_attributes(code: "provider.missing_parameter")
    end
  end

  context "с корневым массивом" do
    let(:read_schema) do
      { type: "array", items: { type: "object", properties: { status: status_schema } } }
    end

    it "читает ответ с одной записью без потери индекса" do
      reply(:get, "/payouts/payout-1", [{ status: "completed" }])
      expect(service.fetch_status(payment)).to eq("approved")
    end
  end

  context "с локальной пробой Location" do
    before do
      location_response(type: "string", format: "uri",
                        example: "https://provider.test/payouts/header-id")
    end

    it "использует объявленный заголовок и код ответа в локальном StubServer" do
      tester = Service::AdapterBuilder::Testing::Tester.new(rules)
      checks = tester.call(source: result.source, blueprint: result.blueprint)
      expect(checks.failed.map(&:detail)).to be_empty
    end
  end

  context "с контрактом plain_client" do
    let(:result) do
      Rsocket.builder(rules: rules("plain_client"), spec_source: Adapter::Loader::Text::SpecReader.new)
             .call(reference: document.to_json, provider: "regression")
    end
    let(:namespace) { Module.new.tap { |space| space.module_eval(result.source) } }
    let(:service) { namespace.const_get(:Payouts).const_get(:RegressionClient).new }

    it "сохраняет поддержку кодирования ID во втором контракте" do
      reply(:get, "/payouts/a%2Fb", status: "completed")
      expect(service.payout_state("a/b")).to eq(:paid)
    end

    it "извлекает Location во втором контракте" do
      location_response
      reply(:post, "/payouts", {}, "Location" => "https://provider.test/payouts/header-id")
      expect(service.send_payout({})).to eq("header-id")
    end

    it "отказывает при отсутствии ID в успешном ответе создания" do
      reply(:post, "/payouts", {})
      expect do
        service.send_payout({})
      end.to raise_error(service.class::ProviderError, /missing_operation_id/)
    end
  end

  it "согласует ID тестовой заявки с example внутри схемы ответа" do
    create_schema[:example] = { id: "documented-id" }
    fixture = Service::AdapterBuilder::Testing::Payment.new(result.blueprint)
    expect(fixture.provider_id).to eq("documented-id")
  end
end

# rubocop:enable RSpec/MultipleMemoizedHelpers
