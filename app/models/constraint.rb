# frozen_string_literal: true

module Models
  # Предпроверка: выражение, граница и её вид в коде. kind общий для контрактов.
  class Constraint
    COMPARISONS = { less_than: "<", greater_than: ">" }.freeze
    CURRENCY = :currency

    attr_reader :kind, :comparison, :value, :code, :constant, :subject, :source

    # @param kind [Symbol] вид ограничения: :min_amount, :max_amount или :currency
    # @param code [String] код отказа контракта, например amount_too_low
    # @param constant [String] имя константы, в которой ограничение напечатается
    # @param subject [String] выражение контракта, которое проверяем: operation.amount
    # @param source [String] откуда взято ограничение — словами, для человека
    # @param comparison [Symbol, nil] :less_than или :greater_than; nil для перечисления
    # @param value [Integer, Float, Array<String>, nil] граница или список значений
    def initialize(kind:, code:, constant:, subject:, source:, comparison: nil, value: nil)
      @kind = kind
      @comparison = comparison
      @value = value
      @code = code
      @constant = constant
      @subject = subject
      @source = source
    end

    # @return [Boolean] проверяем список значений, а не границу числа
    def currency? = kind == CURRENCY

    # @return [String] знак сравнения для сгенерированного условия
    # @raise [KeyError] у ограничения нет сравнения (перечисление валют)
    def operator
      COMPARISONS.fetch(comparison)
    end
  end
end
