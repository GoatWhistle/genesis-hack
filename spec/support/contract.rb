# frozen_string_literal: true

# Замена контракта заказчика на время проверок. Настоящий Provider::BaseService
# нам не передали, поэтому здесь ровно те методы, которые вызывает обёртка, —
# по примеру из описания задачи.
Result = Struct.new(:ok, :status, :code, keyword_init: true) do
  def failed? = !ok
end

# Операция заказчика: обёртка читает у неё сумму, валюту и реквизиты.
Operation = Struct.new(:id, :amount, :currency, :payout_requisite, :provider_operation_id,
                       :description, keyword_init: true)

def stub_contract
  base = Class.new do
    def check_conditions(_operation, _request_method) = success
    def success = Result.new(ok: true)
    def failure(status, code) = Result.new(ok: false, status: status, code: code)
    def approve_operation(id) = { approved: id }
    def reject_operation(id, code) = { rejected: [id, code] }
  end
  Object.const_set(:Provider, Class.new) unless Object.const_defined?(:Provider)
  Provider.const_set(:BaseService, base) unless Provider.const_defined?(:BaseService)
end
