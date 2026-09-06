# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Classification
      # Раздача ролей. Роли не независимы: статус и отмена обязаны относиться к
      # тому же переводу, который создаёт create-операция, поэтому сначала
      # выбирается операция создания, а остальные подбираются к ней по связям.
      # Занятая операция в следующих ролях не участвует.
      class Classifier
        Candidate = Struct.new(:operation, :score, :structure, :matched_rules,
                               keyword_init: true) do
          # @return [Integer] порядок кандидатов: слова плюс поправка структуры
          def rank = score + structure
        end

        # Сколько соперников печатается в объяснении неоднозначности.
        RIVALS = 3

        # @param rules [Ports::Rules] роли, их правила и пороги
        def initialize(rules)
          @rules = rules
        end

        # @param operations [Array<Models::ApiOperation>] все операции описания
        # @return [Hash{Symbol => Models::RoleBinding}] роль → привязка, включая заглушки
        def call(operations)
          ranked = @rules.ordered_roles.to_h { |role| [role.name, rank(role, operations)] }
          origin = Anchor.new(@rules).call(ranked)
          claimed = []
          @rules.ordered_roles.to_h do |role|
            binding = bind(role, ranked.fetch(role.name), claimed, origin)
            claimed << binding.operation if binding.bound?
            [role.name, binding]
          end
        end

        private

        # @param role [Config::Settings::Role]
        # @param candidates [Array<Candidate>] кандидаты роли по убыванию счёта
        # @param claimed [Array<Models::ApiOperation>] операции, занятые другими ролями
        # @param origin [Models::ApiOperation, nil] выбранная операция создания
        # @return [Models::RoleBinding]
        def bind(role, candidates, claimed, origin)
          available = candidates.reject { |item| claimed.include?(item.operation) }
          allowed = available.select { |item| item.score >= role.threshold }
          return unbound(role, nothing_fits(role, available)) if allowed.empty?

          chosen = choose(role, allowed, origin)
          return unbound(role, unlinked(role, allowed, origin)) if chosen.nil?

          bound(role, chosen, allowed, origin)
        end

        # @param role [Config::Settings::Role]
        # @param available [Array<Candidate>] незанятые кандидаты роли
        # @return [String] почему роль осталась заглушкой
        def nothing_fits(role, available)
          return "ни одна операция описания не подошла" if available.empty?

          below_threshold(role, available.first)
        end

        # @return [String] почему связанного кандидата не нашлось
        def unlinked(role, allowed, origin)
          return "создание выплаты не распознано, роль #{role.name} без него не имеет смысла" if
            origin.nil?

          "связь с созданием не подтверждена ни у одного кандидата: " \
            "#{allowed.first(RIVALS).map { |item| item.operation.method_name }.join(", ")}"
        end

        # Роль создания уже выбрана. Статус и отмена относятся к той же выплате,
        # поэтому берётся кандидат с подтверждённой связью; кандидат без связи
        # роль не занимает — отказ понятнее неверной операции.
        # @return [Candidate, nil] nil — связанного кандидата не нашлось
        def choose(role, allowed, origin)
          return allowed.find { |item| item.operation.equal?(origin) } || allowed.first if
            role.trait?(:creates_operation)
          return allowed.first if role.trait?(:receives_callback)
          return nil if origin.nil?

          Anchor.linked(allowed, origin, role).first
        end

        # @return [Models::RoleBinding]
        def bound(role, chosen, allowed, origin)
          Models::RoleBinding.new(role: role, operation: chosen.operation, score: chosen.score,
                                  matched_rules: chosen.matched_rules,
                                  alternatives: rivals(chosen, allowed),
                                  link: link_of(role, chosen, origin))
        end

        # Соперники: кандидаты не хуже выбранного по очкам. Их наличие и есть
        # неоднозначность, и она должна быть видна в отчёте.
        # @return [Array<String>]
        def rivals(chosen, allowed)
          allowed.reject { |item| item.operation.equal?(chosen.operation) }
                 .select { |item| item.rank >= chosen.rank }
                 .first(RIVALS)
                 .map { |item| "#{item.operation.method_name} (счёт #{item.score})" }
        end

        # @return [String, nil] чем подтверждена связь роли с созданием
        def link_of(role, chosen, origin)
          return nil if origin.nil? || role.trait?(:creates_operation)
          return nil if role.trait?(:receives_callback)

          Coherence.explain(origin, chosen.operation)
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
          scored.sort_by { |candidate, position| [-candidate.rank, position] }.map(&:first)
        end

        # @param role [Config::Settings::Role]
        # @param operation [Models::ApiOperation]
        # @param position [Integer] номер операции в описании, используется при равенстве счёта
        # @return [Array(Candidate, Integer), nil] nil, если сработало veto
        def score(role, operation, position)
          result = role.score(operation)
          return nil if result.nil?

          candidate = Candidate.new(operation: operation, score: result[0],
                                    matched_rules: result[1], structure: result[2])
          [candidate, position]
        end
      end
    end
  end
end
