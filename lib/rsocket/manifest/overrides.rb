# frozen_string_literal: true

require_relative "../classify/result"

module Rsocket
  module Manifest
    # Правки человека в значениях: перевод статусов, классы ошибок, единицы
    # суммы, разбор уведомлений.
    #
    # Живут отдельно от правок ролей: роль выбирается из операций описания и её
    # ещё надо найти, а здесь простые значения, которые инженер меняет прямо в
    # файле. Правило у них общее — переопределяем только то, что отличается от
    # нашего вывода, иначе файл прошлого прогона затирал бы обоснования.
    class Overrides
      SIGNAL = :manifest

      def initialize(document)
        @document = document || {}
      end

      # Перевод статусов правят чаще всего: значение из файла заменяет наше и
      # добавляет то, чего мы не нашли вовсе.
      def statuses(computed)
        changed = changed_statuses(computed)
        kept = computed.reject { |status| changed.key?(status.provider_value) }
        kept + changed.map { |value, canonical| status_mapping(value, canonical) }
      end

      def errors(computed)
        by_code = section("errors")["by_http_code"] || {}
        by_provider = section("errors")["by_provider_code"] || {}
        computed.map { |error| override_error(error, by_code, by_provider) }
      end

      # Единицы суммы — то место, ради которого файл догадок в первую очередь и
      # нужен: в описаниях они часто лежат текстом, а не структурой.
      def money(computed)
        override = section("money")
        return computed if blank?(override["unit"])
        return computed if computed&.unit.to_s == override["unit"].to_s

        Rsocket::Classify::MoneyDecision.new(
          unit: override["unit"].to_sym, field_path: override["field"] || computed&.field_path,
          evidence: [evidence("единицы суммы заданы человеком в файле догадок")]
        )
      end

      def webhook(computed)
        override = section("webhook")
        return computed if computed.nil? || override.empty?

        computed.with(
          signature_header: override["signature_header"] || computed.signature_header,
          algorithm: (override["algorithm"] || computed.algorithm).to_sym,
          event_field: override["event_field"] || computed.event_field,
          status_field: override["status_field"] || computed.status_field
        )
      end

      private

      def changed_statuses(computed)
        known = computed.to_h { |status| [status.provider_value, status.canonical] }
        section("statuses").reject do |value, canonical|
          blank?(canonical) || known[value].to_s == canonical.to_s
        end
      end

      def status_mapping(value, canonical)
        Rsocket::Classify::StatusMapping.new(
          provider_value: value, canonical: canonical.to_sym, verdict: :confident,
          evidence: [evidence("перевод задан человеком в файле догадок")]
        )
      end

      def override_error(error, by_code, by_provider)
        klass = by_provider[error.provider_code] || by_code[error.http_code.to_s]
        return error if blank?(klass) || klass.to_sym == error.klass

        error.with(klass: klass.to_sym,
                   evidence: [evidence("класс ошибки задан человеком в файле догадок")])
      end

      def section(name) = @document[name].is_a?(Hash) ? @document[name] : {}

      def blank?(value) = value.nil? || value.to_s.strip.empty?

      def evidence(detail)
        Rsocket::Classify::Evidence.new(signal: SIGNAL, weight: 0.0, detail: detail)
      end
    end
  end
end
