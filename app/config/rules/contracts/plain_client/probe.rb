# frozen_string_literal: true

# Проба контракта «обычный клиент»: платёж хешем, отказ исключением.

class Probe
  # Число аргументов определяет сам метод: запрос состояния бывает и с телом.
  # @param class_name [String] имя собранного класса, например NovapayClient
  def initialize(class_name)
    @subject = Payouts.const_get(class_name).new
  end

  # @param role [Symbol] роль контракта, она же имя метода клиента
  # @param payment [Hash] заявка тестера
  # @return [Hash] { ok:, code:, value: }
  def call(role, payment)
    { ok: true, code: nil, value: @subject.public_send(role, *arguments(role, payment)) }
  rescue StandardError => e
    { ok: false, code: e.respond_to?(:code) ? e.code : nil, value: nil, error: e.message }
  end

  # @param role [Symbol] роль, разбирающая уведомление
  # @param payload [Hash] тело уведомления
  # @return [Hash] { ok:, status: } — состояние, которым обернулось уведомление
  def callback(role, payload)
    result = @subject.public_send(role, payload)
    { ok: true, status: result[:state] }
  rescue StandardError => e
    { ok: false, status: nil, error: e.message }
  end

  private

  # @param role [Symbol]
  # @param payment [Hash] заявка тестера
  # @return [Array] аргументы вызова в том порядке, в каком их ждёт метод
  def arguments(role, payment)
    values = if creates?(role)
               [body(payment)]
             else
               [payment.fetch(:provider_id), body(payment)]
             end
    values.first(@subject.method(role).arity.abs)
  end

  # Выплату отправляет метод, который принимает платёж, а не идентификатор:
  # у него один аргумент и нет параметра пути.
  # @param role [Symbol]
  # @return [Boolean]
  def creates?(role) = @subject.method(role).parameters.map(&:last) == [:payment]

  # @param payment [Hash] заявка тестера
  # @return [Hash] платёж в том виде, в каком его читает клиент
  def body(payment)
    { external_id: payment.fetch(:id), amount: payment.fetch(:amount),
      currency: payment.fetch(:currency), description: payment.fetch(:description),
      recipient: payment.fetch(:requisite) }
  end
end
