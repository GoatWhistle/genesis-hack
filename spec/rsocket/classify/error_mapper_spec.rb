# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::ErrorMapper do
  def by_http_code(provider)
    described_class.new(classify_context(provider)).call
                   .select(&:http_code).to_h { |error| [error.http_code, error.klass] }
  end

  def by_provider_code(provider)
    described_class.new(classify_context(provider)).call
                   .select(&:provider_code).to_h { |error| [error.provider_code, error.klass] }
  end

  it "относит коды ответов к классам по словарю" do
    expect(by_http_code("novapay")).to include(
      401 => :auth, 422 => :validation, 429 => :limit, 500 => :retryable
    )
  end

  # Повторять 404 бессмысленно, а 402 — осмысленно: деньги на балансе появятся.
  it "различает окончательные и повторяемые отказы" do
    expect(by_http_code("novapay")).to include(404 => :final, 402 => :retryable)
  end

  it "разбирает каталог кодов ошибок провайдера" do
    expect(by_provider_code("novapay")).to include(
      "rate_limit_exceeded" => :limit, "insufficient_balance" => :retryable,
      "recipient_not_found" => :final, "validation_error" => :validation
    )
  end

  it "находит причины отказа, перечисленные внутри успешного ответа" do
    expect(by_provider_code("swiftpay")).to include("beneficiary_account_closed" => :final)
  end

  it "объясняет решение словами" do
    found = described_class.new(classify_context("novapay")).call.first

    expect(found.evidence.first.detail).to include("код ответа 400 отнесён словарём")
  end

  it "работает на описании, где ошибки почти не описаны" do
    expect(by_http_code("kassabox").keys).to contain_exactly(400, 401, 409)
  end
end
