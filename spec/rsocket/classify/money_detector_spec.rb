# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::MoneyDetector do
  def decision(provider)
    described_class.new(classify_context(provider)).call
  end

  # Единицы суммы — самая дорогая ошибка подключения, поэтому проверяем оба
  # исхода на настоящих описаниях, а не на выдуманных.
  it "определяет минимальные единицы там, где сумма целая" do
    expect(decision("novapay").unit).to eq(:minor)
  end

  it "определяет дробное число там, где сумма дробная" do
    expect(decision("swiftpay").unit).to eq(:decimal)
  end

  it "находит сумму внутри вложенного объекта" do
    expect(decision("kassabox").field_path).to eq("sum.value")
  end

  it "обосновывает вывод словами описания" do
    expect(decision("novapay").evidence.map(&:detail))
      .to include(a_string_matching(/описание поля говорит «копейк»/))
  end

  it "обосновывает вывод порядком величины" do
    expect(decision("novapay").evidence.map(&:detail))
      .to include(a_string_matching(/минимум равен 100000/))
  end

  it "не делает вывода, когда поля суммы нет" do
    expect(empty_decision.unit).to be_nil
  end

  it "говорит, почему вывода нет" do
    expect(empty_decision.evidence.first.detail).to include("поле суммы в описании не найдено")
  end

  def empty_decision
    dictionaries = Rsocket::Dictionaries.default
    context = Rsocket::Classify::Context.new(
      spec: Rsocket::Ir::Spec.new(operations: []), dictionaries: dictionaries,
      roles: Rsocket::Classify::Roles.default(dictionaries)
    )
    described_class.new(context).call
  end
end
