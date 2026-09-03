# frozen_string_literal: true

module Rsocket
  module Classify
    # Сумма весов, пороги, вердикт.
    #
    # Три вердикта вместо двух — осознанное решение. «Не определено» инженер
    # закроет за минуту, неверно определённое найдёт в проде через неделю,
    # поэтому ниже нижнего порога инструмент молчит, а не угадывает.
    class Scoring
      DEFAULTS = {
        "confident" => 5.0, "needs_confirmation" => 2.0, "min_signals_for_confident" => 2
      }.freeze

      def initialize(weights = {})
        @thresholds = DEFAULTS.merge(weights["thresholds"] || {})
      end

      def score(evidence)
        Array(evidence).sum(&:weight).round(2)
      end

      def verdict(evidence)
        value = score(evidence)
        return :unknown if value < @thresholds["needs_confirmation"]
        return :needs_confirmation if value < @thresholds["confident"]
        return :needs_confirmation unless enough_signals?(evidence)

        :confident
      end

      def considered?(evidence)
        score(evidence) >= @thresholds["needs_confirmation"]
      end

      private

      # Одно совпадение слов — это совпадение слов, а не понимание смысла.
      # Уверенный вердикт требует, чтобы роль подтвердилась разными способами:
      # словами и формой запроса, формой и связями по идентификаторам.
      def enough_signals?(evidence)
        evidence.map(&:signal).uniq.size >= @thresholds["min_signals_for_confident"]
      end
    end
  end
end
