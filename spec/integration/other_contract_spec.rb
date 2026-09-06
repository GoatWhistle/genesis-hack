# frozen_string_literal: true

require "webmock/rspec"

# По тому же описанию собирается класс под другой контракт.
RSpec.describe "сборка под контракт plain_client" do
  subject(:client) { Payouts::NovapayClient.new }

  before(:all) { load_service("novapay", contract: "plain_client") }

  let(:source) { build_service("novapay", contract: "plain_client").source }
  let(:payment) do
    { amount: 15_000, currency: "RUB", external_id: "op_abc123",
      recipient: { "phone" => "79001234567", "bank_code" => "044525225" } }
  end

  before { ENV["NOVAPAY_API_KEY"] = "ключ" }

  describe "распознавание чужого API" do
    # Правила общие: роли зовутся иначе, но операции разошлись так же.
    it "отдаёт ролям контракта те же операции провайдера" do
      bindings = build_service("novapay", contract: "plain_client").blueprint.bindings
      expect(bindings.transform_values { |binding| binding.operation&.method_name })
        .to eq(send_payout: "create_payout", payout_state: "get_payout_status",
               read_callback: "payout_webhook", cancel_payout: "cancel_payout")
    end

    it "называет контракт в отчёте" do
      expect(build_service("novapay", contract: "plain_client").report)
        .to include("contract" => "plain_client")
    end
  end

  describe "печать" do
    it "печатает синтаксически верный Ruby" do
      expect { RubyVM::InstructionSequence.compile(source) }.not_to raise_error
    end

    it "называет класс так, как велит контракт" do
      expect(source).to include("class NovapayClient", "module Payouts")
    end

    it "печатает методы своего контракта" do
      expect(source.scan(/def (\w+)/).flatten)
        .to include("send_payout", "payout_state", "cancel_payout", "read_callback")
    end

    it "не печатает методов чужого контракта" do
      expect(source).not_to include("def create_request", "BaseService")
    end

    it "переводит состояния в словарь своего контракта" do
      expect(source).to include('"completed" => :paid', '"failed" => :declined')
    end

    it "берёт ограничения из того же описания, но со своими кодами" do
      expect(source).to include("MIN_AMOUNT = 1000", 'raise InvalidPayment, "amount_below_minimum"')
    end
  end

  describe "отправка выплаты" do
    before do
      stub_request(:post, "https://api.sandbox.novapay.example/v1/payouts")
        .to_return(status: 201, headers: { "Content-Type" => "application/json" },
                   body: { id: "np_7f3a9b2c", status: "pending" }.to_json)
    end

    it "уходит на адрес провайдера с суммой в копейках" do
      client.send_payout(payment)
      expect(a_request(:post, "https://api.sandbox.novapay.example/v1/payouts")
        .with(body: hash_including("amount" => 1_500_000, "currency" => "RUB"))).to have_been_made
    end

    it "достаёт реквизиты оттуда, где их держит этот контракт" do
      client.send_payout(payment)
      expect(a_request(:post, "https://api.sandbox.novapay.example/v1/payouts")
        .with(body: hash_including("recipient" => hash_including("phone" => "79001234567"))))
        .to have_been_made
    end

    it "возвращает идентификатор значением, а не пишет его в операцию" do
      expect(client.send_payout(payment)).to eq("np_7f3a9b2c")
    end

    it "не выпускает платёж, нарушающий ограничение провайдера" do
      expect { client.send_payout(payment.merge(amount: 999)) }
        .to raise_error(Payouts::NovapayClient::InvalidPayment, "amount_below_minimum")
    end
  end

  describe "ошибка провайдера" do
    before do
      stub_request(:get, "https://api.sandbox.novapay.example/v1/payouts/np_7f3a9b2c")
        .to_return(status: 429, body: "{}", headers: { "Content-Type" => "application/json" })
    end

    it "отказывается исключением, а не возвращает отказ значением" do
      expect { client.payout_state("np_7f3a9b2c") }
        .to raise_error(Payouts::NovapayClient::ProviderError)
    end

    it "переводит код ответа в код ошибки контракта" do
      expect { client.payout_state("np_7f3a9b2c") }
        .to raise_error(an_object_having_attributes(code: :rate_limited, http_code: 429,
                                                    retriable?: true))
    end
  end

  describe "разбор уведомления" do
    it "отдаёт разобранное уведомление хешем" do
      payload = { "event" => "payout.failed", "payout_id" => "np_7f3a9b2c",
                  "error" => { "code" => "recipient_not_found" } }
      expect(client.read_callback(payload))
        .to eq(id: "np_7f3a9b2c", state: :declined, error: "recipient_not_found")
    end
  end
end
