# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Classification
      # Раздача ролей: занятая операция в следующих ролях не участвует.
      class Classifier
        Candidate = Struct.new(:operation, :score, :matched_rules, keyword_init: true)

        # @param rules [Ports::Rules] роли, их правила и пороги
        def initialize(rules)
          @rules = rules
        end

        # Назначает каждой роли операцию с наибольшим счётом среди свободных.
        # @param operations [Array<Models::ApiOperation>] все операции описания
        # @return [Hash{Symbol => Models::RoleBinding}] роль → привязка, включая заглушки
        def call(operations)
          claimed = []
          @rules.ordered_roles.to_h do |role|
            binding = bind(role, operations - claimed)
            claimed << binding.operation if binding.bound?
            [role.name, binding]
          end
        end

        private

        # @param role [Config::Settings::Role]
        # @param available [Array<Models::ApiOperation>] операции, ещё не занятые другими ролями
        # @return [Models::RoleBinding] пустая привязка, если кандидатов нет или лучший ниже порога
        def bind(role, available)
          best = rank(role, available).first
          return unbound(role, "ни одна операция описания не подошла") if best.nil?
          return unbound(role, below_threshold(role, best)) if best.score < role.threshold

          Models::RoleBinding.new(role: role, operation: best.operation,
                                  score: best.score, matched_rules: best.matched_rules)
        end

        # @param role [Config::Settings::Role]
        # @param reason [String] почему роль не занята; попадает в отчёт и в код
        # @return [Models::RoleBinding]
        def unbound(role, reason)
          Models::RoleBinding.new(role: role, reason: reason)
        end

        # @param role [Config::Settings::Role]
        # @param best [Candidate] лучший кандидат, не набравший порога
        # @return [String]
        def below_threshold(role, best)
          "лучший кандидат #{best.operation.method_name} набрал #{best.score} " \
            "при пороге #{role.threshold}"
        end

        # Кандидаты по убыванию счёта; при равенстве побеждает объявленный раньше.
        # @param role [Config::Settings::Role]
        # @param available [Array<Models::ApiOperation>]
        # @return [Array<Candidate>]
        def rank(role, available)
          scored = available.each_with_index.filter_map do |operation, position|
            score(role, operation, position)
          end
          scored.sort_by { |candidate, position| [-candidate.score, position] }.map(&:first)
        end

        # @param role [Config::Settings::Role]
        # @param operation [Models::ApiOperation]
        # @param position [Integer] номер операции в описании, используется при равенстве счёта
        # @return [Array(Candidate, Integer), nil] nil, если сработало veto
        def score(role, operation, position)
          result = role.score(operation)
          return nil if result.nil?

          candidate = Candidate.new(operation: operation, score: result.first,
                                    matched_rules: result.last)
          [candidate, position]
        end
      end
    end
  end
end
