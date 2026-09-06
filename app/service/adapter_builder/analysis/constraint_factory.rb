# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Найденное ограничение → предпроверка контракта.
      class ConstraintFactory
        # @param rules [Ports::Rules] описание предпроверок контракта
        def initialize(rules)
          @rules = rules
        end

        # @param kind [Symbol] :min_amount, :max_amount или :currency
        # @param source [String] источник ограничения в текстовом виде
        # @param value [Integer, Float, Array<String>] граница или список значений
        # @param comparison [Symbol, nil] :less_than или :greater_than; nil для перечисления
        # @return [Models::Constraint, nil] nil, если контракт такую проверку не выполняет
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
