# frozen_string_literal: true

require "webmock/rspec"

# Самая честная проверка: собираем сервис, грузим его как обычный файл и смотрим,
# какой запрос уходит на провод. Ничего внешнего для этого больше не нужно —
# сервис ходит к провайдеру сам.
RSpec.describe "сгенерированный сервис" do
  subject(:service) { Provider::NovapayService.new }

  # Контракт заказчика: BaseService нам не передали, поэтому в тесте живёт его
  # минимальная замена — ровно те методы, которые сервис вызывает.
  before(:all) do
    stub_contract
    load_service("novapay")
    load_service("swiftpay")
  end

  let(:operation) do
    instance_double(Operation, id: "op_abc123", amount: 15_000, currency: "RUB",
                               description: "выплата по операции", payout_requisite: requisite)
  end

  let(:requisite) { { "sbp" => { "phone" => "79001234567", "bank_code" => "044525225" } } }

  before { ENV["NOVAPAY_API_KEY"] = "ключ" }

  describe "создание выплаты" do
    before do
      allow(operation).to receive(:provider_operation_id=)
      stub_request(:post, "https://api.sandbox.novapay.example/v1/payouts")
        .to_return(status: 201, headers: { "Content-Type" => "application/json" },
                   body: { id: "np_7f3a9b2c", status: "pending" }.to_json)
    end

    it "уходит на адрес провайдера с суммой в копейках" do
      service.create_request(operation)
      expect(a_request(:post, "https://api.sandbox.novapay.example/v1/payouts")
        .with(body: hash_including("amount" => 1_500_000, "currency" => "RUB",
                                   "external_id" => "op_abc123"))).to have_been_made
    end

    it "достаёт реквизиты из вложенного раздела payout_requisite" do
      service.create_request(operation)
      recipient = hash_including("phone" => "79001234567", "type" => "sbp")
      expect(a_request(:post, "https://api.sandbox.novapay.example/v1/payouts")
        .with(body: hash_including("recipient" => recipient))).to have_been_made
    end

    it "передаёт ключ авторизации и ключ идемпотентности" do
      service.create_request(operation)
      headers = { "X-API-Key" => "ключ", "Idempotency-Key" => "op_abc123",
                  "Content-Type" => "application/json" }
      expect(a_request(:post, "https://api.sandbox.novapay.example/v1/payouts")
        .with(headers: headers)).to have_been_made
    end

    it "запоминает идентификатор операции у провайдера" do
      service.create_request(operation)
      expect(operation).to have_received(:provider_operation_id=).with("np_7f3a9b2c")
    end
  end

  describe "статус-запрос" do
    before do
      allow(operation).to receive(:provider_operation_id).and_return("np_7f3a9b2c")
      stub_request(:get, "https://api.sandbox.novapay.example/v1/payouts/np_7f3a9b2c")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { id: "np_7f3a9b2c", status: "completed" }.to_json)
    end

    it "подставляет идентификатор провайдера прямо в адрес" do
      service.fetch_status(operation)
      expect(a_request(:get, "https://api.sandbox.novapay.example/v1/payouts/np_7f3a9b2c"))
        .to have_been_made
    end

    it "переводит состояние провайдера в статус контракта" do
      expect(service.fetch_status(operation)).to eq("approved")
    end
  end

  describe "предпроверки" do
    it "не пропускает сумму ниже минимума провайдера" do
      allow(operation).to receive(:amount).and_return(999)
      expect(service.check_conditions(operation, "create"))
        .to have_attributes(code: "amount_too_low")
    end

    it "пропускает сумму в пределах ограничений" do
      expect(service.check_conditions(operation, "create")).to have_attributes(ok: true)
    end
  end

  describe "обработка webhook" do
    it "утверждает операцию по событию об успехе" do
      payload = { "event" => "payout.completed", "payout_id" => "np_7f3a9b2c" }
      expect(service.process_callback(payload)).to eq(approved: "np_7f3a9b2c")
    end

    it "отклоняет операцию с кодом ошибки провайдера" do
      payload = { "event" => "payout.failed", "payout_id" => "np_7f3a9b2c",
                  "error" => { "code" => "recipient_not_found" } }
      expect(service.process_callback(payload))
        .to eq(rejected: %w[np_7f3a9b2c recipient_not_found])
    end
  end

  describe "ошибка провайдера" do
    before do
      allow(operation).to receive(:provider_operation_id).and_return("np_7f3a9b2c")
      stub_request(:get, "https://api.sandbox.novapay.example/v1/payouts/np_7f3a9b2c")
        .to_return(status: 429, body: "{}", headers: { "Content-Type" => "application/json" })
    end

    it "переводит код ответа в код ошибки контракта" do
      expect(service.fetch_status(operation)).to have_attributes(status: :too_many_requests,
                                                                 code: "provider.rate_limit")
    end
  end

  describe "когда провайдер не ответил" do
    before do
      allow(operation).to receive(:provider_operation_id).and_return("np_7f3a9b2c")
      stub_request(:get, "https://api.sandbox.novapay.example/v1/payouts/np_7f3a9b2c")
        .to_timeout
    end

    it "не путает обрыв связи с отказом провайдера" do
      expect(service.fetch_status(operation)).to have_attributes(code: "provider.transport_error")
    end
  end

  # Второй провайдер нужен ради другой схемы авторизации: bearer вместо ключа.
  describe "другой провайдер" do
    subject(:service) { Provider::SwiftpayService.new }

    before do
      ENV["SWIFTPAY_ACCESS_TOKEN"] = "токен"
      allow(operation).to receive(:provider_operation_id=)
      stub_request(:post, "https://sandbox.swiftpay.example/api/v2/transfers")
        .to_return(status: 202, headers: { "Content-Type" => "application/json" },
                   body: { transfer_id: "trf_01", state: "new" }.to_json)
    end

    it "подписывает запрос токеном, а не ключом в заголовке" do
      service.create_request(operation)
      expect(a_request(:post, "https://sandbox.swiftpay.example/api/v2/transfers")
        .with(headers: { "Authorization" => "Bearer токен" })).to have_been_made
    end
  end
end
