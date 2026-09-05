# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Найденное ограничение → предпроверка в словах контракта. Вид ограничения
      # внутренний и одинаков для всех контрактов, а код отказа, имя константы и
      # выражение, которое проверяется, у каждого свои и лежат в его конфиге.
      # Контракт, который такую проверку не делает, просто её не описывает.
      class ConstraintFactory
        # @param rules [Ports::Rules] описание предпроверок контракта
        def initialize(rules)
          @rules = rules
        end

        # @param kind [Symbol] :min_amount, :max_amount или :currency
        # @param source [String] откуда взято ограничение — словами, для человека
        # @param value [Integer, Float, Array<String>] граница или список значений
        # @param comparison [Symbol, nil] :less_than или :greater_than; nil для перечисления
        # @return [Models::Constraint, nil] nil, если контракт такого не проверяет
        def call(kind, source:, value:, comparison: nil)
          entry = @rules.condition(kind)
          return nil if entry.nil?

          Models::Constraint.new(kind: kind, comparison: comparison, value: value, source: source,
                                 code: entry.fetch(:code).to_s,
                                 constant: entry.fetch(:constant).to_s,
                                 subject: entry.fetch(:subject).to_s)
        end
      end
    end
  end
end
