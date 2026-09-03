# frozen_string_literal: true

require "spec_helper"
require "json"
require "openssl"

require_relative "../../../reference/novapay_service"

# Образцовый сервис проверяется как настоящая интеграция, а не как заготовка
# под шаблон: если тесты держат его поведение, то и шаблон, рождённый из него,
# будет воспроизводить рабочий код, а не похожий на рабочий.
RSpec.describe Provider::NovapayService do
  subject(:service) { described_class.new }

  let(:base_url) { described_class::BASE_URL }
  let(:api_key) { "test-api-key" }
  let(:callback_secret) { "test-callback-secret" }

  let(:operation) do
    Operation.new(
      id: "op_abc123", amount: 1500, currency: "RUB", provider_operation_id: "np_7f3a9b2c",
      payout_requisite: {
        "sbp" => { "phone" => "79001234567", "bank_code" => "044525225", "bank_name" => "Сбербанк" }
      }
    )
  end

  before do
    ENV["NOVAPAY_API_KEY"] = api_key
    ENV["NOVAPAY_CALLBACK_SECRET"] = callback_secret
  end

  after do
    ENV.delete("NOVAPAY_API_KEY")
    ENV.delete("NOVAPAY_CALLBACK_SECRET")
  end

  def json_response(body, status: 200)
    { status: status, body: JSON.generate(body), headers: { "Content-Type" => "application/json" } }
  end

  def validation_error
    { "error" => { "code" => "validation_error", "message" => "too low" } }
  end

  def rate_limited
    {
      status: 429, body: JSON.generate("error" => { "code" => "rate_limit_exceeded" }),
      headers: { "Content-Type" => "application/json", "Retry-After" => "60" }
    }
  end

  # Уведомление приходит вместе с сырым телом и заголовками: подпись считается
  # от тела, а не от разобранного хеша.
  def signed(payload, secret: callback_secret)
    body = JSON.generate(payload)
    payload.merge(
      described_class::RAW_BODY_KEY => body,
      described_class::HEADERS_KEY => {
        "X-NovaPay-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      }
    )
  end

  describe "#create_request" do
    let(:expected_body) do
      {
        amount: 150_000, currency: "RUB", external_id: "op_abc123",
        recipient: { type: "sbp", phone: "79001234567", bank_code: "044525225",
                     bank_name: "Сбербанк" }
      }
    end

    before do
      stub_request(:post, "#{base_url}/payouts")
        .to_return(json_response({ "id" => "np_7f3a9b2c", "status" => "pending" }, status: 201))
    end

    it "входит по ключу в заголовке и защищается ключом идемпотентности" do
      service.create_request(operation)

      expect(WebMock).to have_requested(:post, "#{base_url}/payouts")
        .with(headers: { "X-API-Key" => api_key, "Idempotency-Key" => "op_abc123" })
    end

    it "отправляет сумму в копейках и получателя со всеми реквизитами" do
      service.create_request(operation)

      expect(WebMock).to have_requested(:post, "#{base_url}/payouts").with(body: expected_body)
    end

    it "запоминает идентификатор выплаты в операции" do
      service.create_request(operation)

      expect(operation.provider_operation_id).to eq("np_7f3a9b2c")
    end

    it "переводит статус создания в статус заказчика" do
      expect(service.create_request(operation).operation_status).to eq("in_progress")
    end
  end

  describe "#create_request, ответы провайдера" do
    it "разбирает повтор по ключу идемпотентности как ту же выплату" do
      stub_request(:post, "#{base_url}/payouts")
        .to_return(json_response({ "id" => "np_7f3a9b2c", "status" => "pending" }, status: 409))

      expect(service.create_request(operation).payload[:duplicate]).to be(true)
    end

    it "превращает 422 в отказ с кодом ошибки провайдера", :aggregate_failures do
      stub_request(:post, "#{base_url}/payouts")
        .to_return(json_response(validation_error, status: 422))

      result = service.create_request(operation)
      expect(result.code).to eq("provider.validation_error")
      expect(result.payload[:provider_code]).to eq("validation_error")
    end

    it "доносит задержку из заголовка при превышении лимита", :aggregate_failures do
      stub_request(:post, "#{base_url}/payouts").to_return(rate_limited)

      result = service.create_request(operation)
      expect(result.code).to eq("provider.rate_limit")
      expect(result.payload).to include(retry_after: 60, action: :retry_backoff)
    end

    it "превращает 401 в отказ, требующий вмешательства дежурного", :aggregate_failures do
      stub_request(:post, "#{base_url}/payouts").to_return(json_response({}, status: 401))

      result = service.create_request(operation)
      expect(result.code).to eq("provider.invalid_credentials")
      expect(result.payload[:action]).to eq(:alert)
    end

    it "превращает 500 в отказ, который имеет смысл повторить" do
      stub_request(:post, "#{base_url}/payouts").to_return(json_response({}, status: 500))

      expect(service.create_request(operation).payload[:action]).to eq(:retry_alert)
    end
  end

  describe "#fetch_status" do
    described_class::STATUS_MAP.each do |provider_status, expected|
      it "переводит статус провайдера #{provider_status} в #{expected}" do
        stub_request(:get, "#{base_url}/payouts/np_7f3a9b2c")
          .to_return(json_response({ "id" => "np_7f3a9b2c", "status" => provider_status }))

        expect(service.fetch_status(operation).operation_status).to eq(expected)
      end
    end

    it "не признаёт незнакомый статус успехом" do
      stub_request(:get, "#{base_url}/payouts/np_7f3a9b2c")
        .to_return(json_response({ "id" => "np_7f3a9b2c", "status" => "settled" }))

      expect(service.fetch_status(operation).operation_status).to eq("in_progress")
    end

    it "сообщает, что выплата не найдена" do
      stub_request(:get, "#{base_url}/payouts/np_7f3a9b2c")
        .to_return(json_response({ "error" => { "code" => "not_found" } }, status: 404))

      expect(service.fetch_status(operation).code).to eq("provider.payout_not_found")
    end
  end

  describe "#process_callback" do
    it "переводит успешное уведомление в approved" do
      payload = signed({ "event" => "payout.completed", "payout_id" => "np_7f3a9b2c",
                         "status" => "completed" })

      expect(service.process_callback(payload).operation_status).to eq("approved")
    end

    it "переводит неуспешное уведомление в rejected" do
      payload = signed({ "event" => "payout.failed", "payout_id" => "np_7f3a9b2c",
                         "status" => "failed", "error" => { "code" => "recipient_not_found" } })

      expect(service.process_callback(payload).operation_status).to eq("rejected")
    end

    it "доносит код ошибки провайдера из уведомления" do
      payload = signed({ "event" => "payout.failed", "payout_id" => "np_7f3a9b2c",
                         "status" => "failed", "error" => { "code" => "recipient_not_found" } })

      expect(service.process_callback(payload).payload[:error_code]).to eq("recipient_not_found")
    end

    it "оставляет промежуточное уведомление в работе" do
      payload = signed({ "event" => "payout.processing", "payout_id" => "np_7f3a9b2c",
                         "status" => "processing" })

      expect(service.process_callback(payload).operation_status).to eq("in_progress")
    end

    it "считает отмену отказом" do
      payload = signed({ "event" => "payout.cancelled", "payout_id" => "np_7f3a9b2c",
                         "status" => "cancelled" })

      expect(service.process_callback(payload).operation_status).to eq("rejected")
    end

    it "отвергает незнакомое событие, а не угадывает его смысл" do
      payload = signed({ "event" => "payout.frozen", "payout_id" => "np_7f3a9b2c" })

      expect(service.process_callback(payload).code).to eq("unknown_event")
    end
  end

  describe "#process_callback, проверка подписи" do
    let(:body) { { "event" => "payout.completed", "payout_id" => "np_7f3a9b2c" } }

    it "принимает уведомление с правильной подписью" do
      expect(service.process_callback(signed(body)).success?).to be(true)
    end

    it "отвергает уведомление, подписанное чужим секретом" do
      payload = signed(body, secret: "wrong-secret")

      expect(service.process_callback(payload).code).to eq("provider.invalid_signature")
    end

    it "отвергает уведомление с испорченной подписью" do
      payload = signed(body)
      payload[described_class::HEADERS_KEY]["X-NovaPay-Signature"] = "deadbeef"

      expect(service.process_callback(payload).code).to eq("provider.invalid_signature")
    end

    it "отвергает уведомление без подписи" do
      expect(service.process_callback(body).code).to eq("provider.invalid_signature")
    end
  end

  describe "#check_conditions" do
    it "пропускает выплату, проходящую по минимальной сумме" do
      expect(service.check_conditions(operation, "create").success?).to be(true)
    end

    it "отказывает, когда сумма ниже минимальной" do
      operation.amount = 999

      expect(service.check_conditions(operation, "create").code).to eq("amount_too_low")
    end

    it "требует БИК банка при выплате через СБП" do
      operation.payout_requisite["sbp"].delete("bank_code")

      expect(service.check_conditions(operation, "create").code).to eq("bank_code_required")
    end

    it "не проверяет условия выплаты у запроса статуса" do
      operation.amount = 1

      expect(service.check_conditions(operation, "status").success?).to be(true)
    end
  end

  describe "перевод суммы в копейки" do
    before do
      stub_request(:post, "#{base_url}/payouts")
        .to_return(json_response({ "id" => "np_1", "status" => "pending" }, status: 201))
    end

    # Классический источник дорогих ошибок: (19.99 * 100).to_i даёт 1998.
    it "не теряет копейку на дробной сумме" do
      operation.amount = 1519.99
      service.create_request(operation)

      expect(WebMock).to have_requested(:post, "#{base_url}/payouts")
        .with(body: hash_including("amount" => 151_999))
    end
  end
end
