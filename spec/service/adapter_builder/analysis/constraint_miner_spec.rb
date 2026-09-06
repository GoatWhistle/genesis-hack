# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Analysis::ConstraintMiner do
  subject(:result) { build_service(provider).blueprint }

  describe "на описании novapay" do
    let(:provider) { "novapay" }

    it "переводит минимум из копеек в валюту контракта" do
      expect(result.constraints).to include(have_attributes(code: "amount_too_low", value: 1000))
    end

    it "умножает сумму на сто" do
      expect(result.amount_multiplier).to eq(100)
    end

    it "собирает список валют из перечисления" do
      expect(result.constraints).to include(have_attributes(code: "unsupported_currency",
                                                            value: %w[RUB]))
    end

    it "объясняет, откуда взялось ограничение" do
      expect(result.constraints.map(&:source)).to all(include("схеме запроса"))
    end
  end

  # «Рубли и копейки через точку» — формат записи, а не копейки: 1500.00 не 150000.
  describe "когда сумма приходит строкой с копейками в описании" do
    let(:provider) { "nordbank" }

    it "не считает её копейками" do
      expect(result.amount_multiplier).to eq(1)
    end

    it "печатает её строкой с двумя знаками" do
      expect(result.amount_expression).to eq('format("%.2f", operation.amount)')
    end
  end

  describe "на описании swiftpay" do
    let(:provider) { "swiftpay" }

    it "оставляет дробную сумму как есть" do
      expect(result.amount_expression).to eq("operation.amount.to_f")
    end

    it "берёт обе границы прямо из схемы" do
      expect(result.constraints).to include(have_attributes(code: "amount_too_low", value: 1.0),
                                            have_attributes(code: "amount_too_high",
                                                            value: 1_000_000.0))
    end

    it "собирает все разрешённые валюты, а не первую" do
      expect(result.constraints).to include(have_attributes(code: "unsupported_currency",
                                                            value: %w[
                                                              RUB KZT
                                                            ]))
    end
  end

  describe "когда сумма лежит во вложенном объекте" do
    let(:provider) { "kassabox" }

    it "находит её и признаёт копейками" do
      expect(result.amount_multiplier).to eq(100)
    end
  end
end
