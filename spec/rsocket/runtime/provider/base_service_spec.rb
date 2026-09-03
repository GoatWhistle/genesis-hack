# frozen_string_literal: true

require "spec_helper"
require "rsocket/runtime"

# Заглушка контракта заказчика — фундамент, на котором стоит вся генерация.
# Если её форма поедет, поедут и сгенерированный сервис, и его тесты, и
# проверяльщик, поэтому она закрыта тестами отдельно от образца.
RSpec.describe Provider::BaseService do
  subject(:service) { service_class.new }

  # Наследник, который ничего не переопределяет: так проверяется именно
  # поведение базового класса, а не чьё-то поверх него.
  let(:service_class) do
    Class.new(described_class) do
      def refuse = failure(:too_many_requests, "provider.rate_limit", retry_after: 60)
      def accept = success(provider_operation_id: "np_1")
      def approve = approve_operation("np_1", event: "payout.completed")
      def reject = reject_operation("np_1", "recipient_not_found")
      def progress = progress_operation("np_1")
    end
  end

  let(:operation) do
    Operation.new(
      id: "op_1", amount: 1500, currency: "RUB",
      payout_requisite: { "sbp" => { "phone" => "79001234567" } }
    )
  end

  describe "форма отказа" do
    subject(:result) { service.refuse }

    it "несёт статус, код и признак неудачи", :aggregate_failures do
      expect(result).to have_attributes(ok: false, status: :too_many_requests,
                                        code: "provider.rate_limit")
      expect(result.failed?).to be(true)
      expect(result.success?).to be(false)
    end

    it "доносит подробности до вызывающей стороны" do
      expect(result.payload).to eq(retry_after: 60)
    end
  end

  describe "форма успеха" do
    subject(:result) { service.accept }

    it "несёт признак успеха и пустой код ошибки", :aggregate_failures do
      expect(result).to have_attributes(ok: true, status: :ok, code: nil)
      expect(result.success?).to be(true)
      expect(result.failed?).to be(false)
    end
  end

  describe "предпроверки по умолчанию" do
    it "пропускает заполненную операцию" do
      expect(service.check_conditions(operation, "create").success?).to be(true)
    end

    it "отказывает, когда не заполнено обязательное поле операции" do
      operation.currency = nil

      expect(service.check_conditions(operation, "create").code).to eq("operation.currency_missing")
    end

    it "отказывает при неположительной сумме" do
      operation.amount = 0

      expect(service.check_conditions(operation, "create").code).to eq("operation.amount_invalid")
    end
  end

  describe "переводы операции в статусы заказчика" do
    it "успех переводит операцию в approved" do
      expect(service.approve.operation_status).to eq(described_class::APPROVED)
    end

    it "отказ переводит операцию в rejected" do
      expect(service.reject.operation_status).to eq(described_class::REJECTED)
    end

    it "промежуточное событие оставляет операцию в работе" do
      expect(service.progress.operation_status).to eq(described_class::IN_PROGRESS)
    end

    it "запоминает переводы, чтобы их мог проверить проверяльщик" do
      service.approve
      service.reject

      expect(service.transitions.map { |t| t[:operation_status] }).to eq(%w[approved rejected])
    end
  end

  describe "нереализованные методы контракта" do
    it "не притворяются работающими" do
      expect { service.create_request(operation) }.to raise_error(NotImplementedError)
    end
  end
end
