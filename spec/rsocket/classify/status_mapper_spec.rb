# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::StatusMapper do
  def mappings(provider)
    described_class.new(classify_context(provider)).call.to_h do |status|
      [status.provider_value, status.canonical]
    end
  end

  it "переводит статусы описания с понятными именами" do
    expect(mappings("novapay")).to eq(
      "pending" => :created, "processing" => :processing, "completed" => :succeeded,
      "failed" => :rejected, "cancelled" => :cancelled
    )
  end

  it "переводит статусы, названные совсем иначе" do
    expect(mappings("swiftpay")).to eq(
      "new" => :created, "sent" => :processing, "paid" => :succeeded, "declined" => :rejected
    )
  end

  it "достаёт статусы из ответа, завёрнутого в конверт" do
    expect(mappings("kassabox")).to include("delivered" => :succeeded, "aborted" => :cancelled)
  end

  it "показывает, откуда взято значение" do
    found = described_class.new(classify_context("kassabox")).call.first

    expect(found.evidence.first.detail).to include("поле «data.state» в ответе 201")
  end

  it "не выдумывает перевод незнакомому значению" do
    unknown = mapper_with(%w[quantum_flux]).call.first

    expect(unknown.canonical).to be_nil
  end

  it "просит подтверждения там, где перевода не нашлось" do
    expect(mapper_with(%w[quantum_flux]).call.first.verdict).to eq(:needs_confirmation)
  end

  # Подменяем перечисление статусов, не трогая файлы примеров: проверяем
  # поведение на незнакомом значении, а не конкретное описание.
  def mapper_with(values)
    field = Rsocket::Ir::Field.new(name: "status", type: "string", enum: values, path: "status")
    response = Rsocket::Ir::Response.new(code: 200, fields: [field])
    operation = Rsocket::Ir::Operation.new(
      http_method: :get, path: "/x", responses: { 200 => response }
    )
    described_class.new(context_with([operation]))
  end

  def context_with(operations)
    dictionaries = Rsocket::Dictionaries.default
    Rsocket::Classify::Context.new(
      spec: Rsocket::Ir::Spec.new(operations: operations), dictionaries: dictionaries,
      roles: Rsocket::Classify::Roles.default(dictionaries)
    )
  end
end
