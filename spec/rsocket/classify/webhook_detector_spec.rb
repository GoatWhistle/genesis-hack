# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::WebhookDetector do
  subject(:info) { described_class.new(classify_context("novapay")).call }

  it "находит операцию приёма уведомлений по её строению" do
    expect(info.operation.path).to eq("/webhooks/payout")
  end

  it "находит заголовок с подписью" do
    expect(info.signature_header).to eq("X-NovaPay-Signature")
  end

  it "узнаёт алгоритм подписи из описания" do
    expect(info.algorithm).to eq(:hmac_sha256)
  end

  it "называет поля события и статуса" do
    expect(info.to_h).to include(event_field: "event", status_field: "status")
  end

  # У провайдера без уведомлений раздела быть не должно: выдуманный вебхук
  # хуже отсутствующего.
  it "ничего не выдумывает там, где уведомлений нет" do
    expect(described_class.new(classify_context("swiftpay")).call).to be_nil
  end
end
