# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::Text do
  describe ".tokens" do
    it "разбивает слитное имя по заглавным буквам" do
      expect(described_class.tokens("createPayout")).to eq(%w[create payout])
    end

    it "разбивает путь и подчёркивания" do
      expect(described_class.tokens("/v1/transfers/{transfer_no}"))
        .to eq(%w[v1 transfers transfer no])
    end

    it "работает с описанием на русском" do
      expect(described_class.tokens("Создать выплату")).to eq(%w[создать выплату])
    end

    it "пропускает пустые источники" do
      expect(described_class.tokens([nil, "", "Баланс"])).to eq(["баланс"])
    end
  end

  describe ".find" do
    it "находит основу внутри слова" do
      expect(described_class.find(%w[payouts], %w[payout])).to eq("payout")
    end

    it "сравнивает короткие слова целиком" do
      expect(described_class.find(%w[renewal], %w[new])).to be_nil
    end

    it "возвращает само слово словаря, чтобы показать его человеку" do
      expect(described_class.find(%w[создать выплату], %w[отмен созда])).to eq("созда")
    end
  end
end
