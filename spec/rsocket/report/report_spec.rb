# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Report::Report do
  let(:provider) { "kassabox" }
  let(:spec) { ir(provider) }
  let(:result) { Rsocket::Classify::Classifier.call(spec) }
  let(:sections) { described_class.new(spec, result).sections }

  def titles(section) = sections.public_send(section).map(&:title)

  it "называет описание, которое разобрали" do
    expect(described_class.new(spec, result).title).to eq("KassaBox Merchant Transfers 2026-08")
  end

  it "считает операции и найденные роли" do
    expect(described_class.new(spec, result).summary)
      .to eq("операций: 4; ролей определено: 4 из 6")
  end

  it "кладёт уверенно понятые роли в первое ведро" do
    expect(titles(:confident)).to include("создание выплаты → POST /v1/transfers")
  end

  it "показывает единицы суммы среди понятого" do
    expect(titles(:confident)).to include(a_string_matching(/сумма передаётся в минимальных/))
  end

  # Отчёт обязан честно перечислять непонятое: без этого инструмент молча
  # выдаёт догадку за знание.
  it "перечисляет то, чего провайдер не описал" do
    expect(titles(:needs_confirmation))
      .to include(a_string_matching(/не описаны ответы с ошибками/))
  end

  it "называет роли, которые не нашлись" do
    expect(titles(:needs_confirmation)).to include(a_string_matching(/«баланс» не определена/))
  end

  it "показывает спорный случай, а не прячет его" do
    expect(titles(:needs_confirmation)).to include(a_string_matching(/претендовали две операции/))
  end

  it "собирает заметки, оставленные ещё при чтении файла" do
    details = sections.needs_confirmation.flat_map(&:details)

    expect(details).to include(a_string_matching(%r{paths\./v1/refunds\.post}))
  end

  it "объясняет каждую находку словами" do
    finding = sections.confident.first

    expect(finding.details).not_to be_empty
  end
end
