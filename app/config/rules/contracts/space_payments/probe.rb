# frozen_string_literal: true

# Проба контракта Space Payments: замена Provider::BaseService и вызов ролей.
# Исполняется в песочнице рядом со сгенерированным классом.

class Provider
  # Ответ контракта: успех или отказ с кодом.
  Result = Struct.new(:ok, :status, :code, keyword_init: true) do
    def failed? = !ok
  end

  # Операция заказчика: сервис читает у неё сумму, валюту и реквизиты.
  Operation = Struct.new(:id, :amount, :currency, :payout_requisite, :provider_operation_id,
                         :description, keyword_init: true)

  # Замена базового класса: те методы, которые вызывает сервис, плюс запись событий.
  class BaseService
    attr_reader :events

    def initialize
      @events = []
    end

    def check_conditions(_operation, _request_method) = success
    def success = Result.new(ok: true)
    def failure(status, code) = Result.new(ok: false, status: status, code: code)
    def approve_operation(id) = record("approved", id)
    def reject_operation(id, code) = record("rejected", id, code)

    private

    def record(status, id, code = nil)
      @events << { status: status, id: id, code: code }
      success
    end
  end
end

# Как этот контракт вызывается и как читается его ответ.
class Probe
  # @param class_name [String] имя собранного класса, например NovapayService
  def initialize(class_name)
    @subject = Provider.const_get(class_name).new
  end

  # Имя роли здесь же и имя метода сервиса — так устроен этот контракт.
  # @param role [Symbol] роль контракта
  # @param payment [Hash] заявка тестера
  # @return [Hash] { ok:, code:, value: }
  def call(role, payment)
    operation = operation(payment)
    result = @subject.public_send(role, operation)
    return { ok: false, code: result.code, value: nil } if failed?(result)

    { ok: true, code: nil, value: value(result, operation) }
  end

  # @param role [Symbol] роль, принимающая уведомление
  # @param payload [Hash] тело уведомления
  # @return [Hash] { ok:, status: } — статус контракта, которым обернулось уведомление
  def callback(role, payload)
    @subject.events.clear
    result = @subject.public_send(role, payload)
    { ok: !failed?(result), status: callback_status(result) }
  end

  private

  # @param payment [Hash] заявка тестера
  # @return [Provider::Operation] операция заказчика в том виде, в каком её ждёт сервис
  def operation(payment)
    Provider::Operation.new(
      id: payment.fetch(:id), amount: payment.fetch(:amount),
      currency: payment.fetch(:currency), payout_requisite: payment.fetch(:requisite),
      provider_operation_id: payment.fetch(:provider_id),
      description: payment.fetch(:description)
    )
  end

  # Создание операции возвращает success, а идентификатор провайдера кладёт в саму
  # операцию — оттуда его и читаем. Остальные роли отдают состояние значением.
  # @param result [Object] что вернул сервис
  # @param operation [Provider::Operation] операция, с которой его звали
  # @return [Object, nil] идентификатор операции у провайдера или её состояние
  def value(result, operation)
    result.is_a?(Provider::Result) ? operation.provider_operation_id : result
  end

  # @param result [Object] что вернул сервис
  # @return [Boolean] отказ ли это
  def failed?(result) = result.is_a?(Provider::Result) && result.failed?

  # Успех без записанного события — уведомление о промежуточном состоянии: сервис
  # ничего не решил, но и не отказал.
  # @param result [Object] что вернул сервис
  # @return [String, nil] статус контракта
  def callback_status(result)
    event = @subject.events.last
    return event.fetch(:status) if event
    return nil if failed?(result)

    "in_progress"
  end
end
