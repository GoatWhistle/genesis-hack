# frozen_string_literal: true

require_relative "result"
require_relative "roles"
require_relative "scoring"

module Rsocket
  module Classify
    # Раздача ролей операциям: кто создаёт выплату, кто читает статус, кто
    # отменяет.
    #
    # Механизм один на все роли и все признаки: каждый признак возвращает список
    # улик с весами, веса складываются, пороги решают, насколько мы уверены. Ни
    # одной роли и ни одного слова провайдера в этом файле нет и быть не должно —
    # они приходят из словарей.
    class RoleMatcher
      # Проигравший кандидат попадает в отчёт, только если он был настоящим
      # соперником. Операция, набравшая пятую часть от победителя, — это не
      # спорный случай, а шум, и человеку он ничего не сообщает.
      DEFAULT_CONFLICT_RATIO = 0.4

      Matched = Data.define(:assignments, :notes)

      def initialize(context, signals, scoring)
        @roles = context.roles
        @spec = context.spec
        @signals = signals
        @scoring = scoring
        @conflict_ratio = conflict_ratio(context)
      end

      def call
        ranked = ranked_candidates
        assigned = assign(ranked)
        Matched.new(assignments: assigned, notes: notes(ranked, assigned))
      end

      private

      def conflict_ratio(context)
        context.dictionaries.weights.dig("thresholds", "conflict_ratio") || DEFAULT_CONFLICT_RATIO
      end

      # Порядок перебора задан целиком данными, без обращения к случайности и
      # без зависимости от порядка ключей: одинаковый вход обязан давать
      # одинаковый результат, это требование хакатона и здравого смысла.
      def ranked_candidates
        candidates.sort_by do |candidate|
          [-candidate.score, candidate.operation.path,
           candidate.operation.http_method.to_s, candidate.role.to_s]
        end
      end

      def candidates
        @spec.operations.flat_map do |operation|
          @roles.filter_map { |role| candidate(operation, role) }
        end
      end

      def candidate(operation, role)
        evidence = @signals.flat_map { |signal| signal.evidence(operation, role) }
        return unless @scoring.considered?(evidence)

        RoleAssignment.new(
          role: role.id, operation: operation, score: @scoring.score(evidence),
          verdict: @scoring.verdict(evidence), evidence: evidence
        )
      end

      # Роль достаётся операции с наибольшей оценкой, и одна операция занимает
      # не больше одной роли: описание, где создание выплаты одновременно
      # оказалось её отменой, — это не результат, а ошибка.
      def assign(ranked)
        taken_roles = []
        taken_operations = []
        ranked.select do |candidate|
          key = operation_key(candidate.operation)
          next false if taken_roles.include?(candidate.role) || taken_operations.include?(key)

          taken_roles << candidate.role
          taken_operations << key
        end
      end

      def operation_key(operation) = [operation.http_method, operation.path]

      def notes(ranked, assigned)
        conflict_notes(ranked, assigned) + missing_role_notes(assigned)
      end

      # Проигравший кандидат обязан попасть в отчёт: именно здесь человек чаще
      # всего и нужен, а молчание выглядит как уверенность, которой у нас нет.
      def conflict_notes(ranked, assigned)
        winners = assigned.to_h { |assignment| [assignment.role, assignment] }
        (ranked - assigned).filter_map do |loser|
          winner = winners[loser.role]
          next if winner.nil? || loser.score < winner.score * @conflict_ratio

          conflict_note(loser, winner)
        end
      end

      def conflict_note(loser, winner)
        Rsocket::Ir::Note.new(
          level: :needs_confirmation, where: where(loser.operation),
          message: "На роль «#{@roles.title(loser.role)}» претендовали две операции: " \
                   "#{describe(winner)} — выбрана, #{describe(loser)} — отклонена. " \
                   "Если выбор неверен, поправьте роль в файле догадок"
        )
      end

      def missing_role_notes(assigned)
        (@roles.ids - assigned.map(&:role)).map do |role|
          Rsocket::Ir::Note.new(
            level: :info, where: "paths",
            message: "Роль «#{@roles.title(role)}» не определена ни для одной операции: " \
                     "либо провайдер её не поддерживает, либо признаков не хватило"
          )
        end
      end

      def describe(candidate)
        "#{where(candidate.operation)} (оценка #{format("%.1f", candidate.score)})"
      end

      def where(operation) = "#{operation.http_method.to_s.upcase} #{operation.path}"
    end
  end
end
