# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Classification
      # Выбор операции создания выплаты — той, вокруг которой собираются остальные
      # роли. Считается не только счёт самой операции: у настоящей выплаты обычно
      # есть свой статус и своя отмена, а у похожей по названию — нет.
      class Anchor
        # Сколько кандидатов на создание рассматривается со связями.
        POOL = 6

        # Насколько кандидат может отстать от лучшего по очкам и всё же победить,
        # если связанные с ним статус и отмена есть, а у лидера их нет.
        GAP = 6

        # Прибавка за подтверждённую связь роли с кандидатом.
        SUPPORT = 3

        # Кандидаты роли, чья связь с операцией создания доказана.
        # @param candidates [Array<#operation, #score>] кандидаты роли
        # @param operation [Models::ApiOperation, nil] операция создания
        # @param role [Config::Settings::Role] роль, для которой ищется связь
        # @return [Array] те же кандидаты, но только связанные
        def self.linked(candidates, operation, role)
          return [] if operation.nil? || role.trait?(:receives_callback)

          candidates.select do |item|
            item.score >= role.threshold && Coherence.linked?(operation, item.operation)
          end
        end

        # @param rules [Ports::Rules] роли, их правила и пороги
        def initialize(rules)
          @rules = rules
        end

        # @param ranked [Hash{Symbol => Array}] кандидаты каждой роли по убыванию счёта
        # @return [Models::ApiOperation, nil] выбранная операция создания
        def call(ranked)
          role = @rules.role_with(:creates_operation)
          return nil if role.nil?

          best = reachable(ranked.fetch(role.name), role).each_with_index.min_by do |item, place|
            [-(item.rank + support(item.operation, ranked, role)), place]
          end
          best&.first&.operation
        end

        private

        # Кандидаты, которых стоит сравнивать по связям: прошедшие порог и
        # отставшие от лучшего не больше чем на GAP.
        # @param candidates [Array]
        # @param role [Config::Settings::Role]
        # @return [Array]
        def reachable(candidates, role)
          pool = candidates.select { |item| item.score >= role.threshold }.first(POOL)
          return pool if pool.empty?

          pool.select { |item| item.rank + GAP >= pool.first.rank }
        end

        # @param operation [Models::ApiOperation] кандидат на создание
        # @param ranked [Hash{Symbol => Array}]
        # @param anchor_role [Config::Settings::Role] роль создания
        # @return [Integer] прибавка за роли, связанные с этим кандидатом
        def support(operation, ranked, anchor_role)
          @rules.ordered_roles.sum do |role|
            next 0 if role.name == anchor_role.name

            self.class.linked(ranked.fetch(role.name), operation, role).empty? ? 0 : SUPPORT
          end
        end
      end
    end
  end
end
