# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Rsocket::Report::Terminal do
  let(:spec) { ir("swiftpay") }
  let(:result) { Rsocket::Classify::Classifier.call(spec) }
  let(:printed) do
    output = StringIO.new
    described_class.new(Rsocket::Report::Report.new(spec, result), output: output).print
    output.string
  end

  it "начинает с названия описания" do
    expect(printed).to include("Описание: SwiftPay Transfer API 2.4.0")
  end

  it "печатает все три раздела" do
    expect(printed).to match(/Понято уверенно.+Требует подтверждения.+Не поддержано/m)
  end

  it "печатает находки с объяснением" do
    expect(printed).to include("создание выплаты → POST /transfers")
  end

  # Пустой раздел печатается словом «ничего»: молчание в отчёте читается как
  # умолчание о проблемах.
  it "не пропускает пустой раздел молча" do
    expect(printed).to include("Не поддержано (0)\n  ничего")
  end
end
