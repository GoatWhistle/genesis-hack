# frozen_string_literal: true

require "spec_helper"
require "rsocket/generate/field_matcher"

RSpec.describe Rsocket::Generate::FieldMatcher do
  subject(:matcher) { described_class.default }

  describe ".normalize" do
    it "разбирает camelCase" do
      expect(described_class.normalize("orderNo")).to eq("order_no")
    end

    it "снимает регистр и схлопывает разделители" do
      expect(described_class.normalize("X-Request-ID")).to eq("x_request_id")
    end

    it "оставляет обычное имя как есть" do
      expect(described_class.normalize("bank_code")).to eq("bank_code")
    end
  end

  describe "#role" do
    {
      "amount" => :amount, "sum" => :amount, "value" => :amount,
      "currency" => :currency,
      "external_id" => :external_id, "merchant_reference" => :external_id,
      "orderNo" => :external_id,
      "recipient" => :recipient, "destination" => :recipient, "payee" => :recipient,
      "transferNo" => :provider_id, "transfer_id" => :provider_id,
      "state" => :status, "status" => :status
    }.each do |name, expected|
      it "узнаёт в поле #{name} роль #{expected}" do
        expect(matcher.role(name)).to eq(expected)
      end
    end

    # Незнакомое имя не должно получать роль по натяжке: поле, которое
    # инструмент не понял, честнее оставить человеку.
    %w[cardToken bank_bic purpose comment meta].each do |name|
      it "не придумывает роль полю #{name}" do
        expect(matcher.role(name)).to be_nil
      end
    end
  end

  describe "расширяемость" do
    subject(:matcher) { described_class.new("amount" => %w[nominal]) }

    # Добавление синонима — правка данных, а не кода. Если этот тест
    # когда-нибудь потребует изменений в field_matcher.rb, значит знание
    # утекло из словаря обратно в механизм.
    it "подхватывает синоним, которого нет в коде" do
      expect(matcher.role("nominal")).to eq(:amount)
    end

    it "нормализует и добавленные синонимы" do
      expect(matcher.role("Nominal")).to eq(:amount)
    end
  end
end
