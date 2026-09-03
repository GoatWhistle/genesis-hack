# frozen_string_literal: true

require_relative "evidence"
require_relative "meanings"
require_relative "result"
require_relative "text"

module Rsocket
  module Classify
    # Перевод статусов провайдера в наш канонический набор.
    #
    # Статусы собираются оттуда, где они реально лежат: из перечислений в
    # схемах и из примеров ответов. Значение, которого нет в словаре, не
    # выбрасывается и не приравнивается к похожему — оно доезжает до отчёта с
    # пустым переводом, чтобы человек дописал его сам.
    class StatusMapper
      def initialize(context)
        @spec = context.spec
        @meanings = Meanings.new(context.dictionaries.fields)
        @dictionary = context.dictionaries.statuses
      end

      def call
        collect.map { |value, source| mapping(value, source) }
      end

      private

      # Значение → где впервые встретилось. Порядок сохраняется, поэтому вывод
      # не зависит от того, как хеш решил разложить ключи.
      def collect
        found = {}
        @spec.operations.each do |operation|
          status_fields(operation).each { |field, where| record(found, field, where) }
        end
        found
      end

      def status_fields(operation)
        response_sources(operation) + request_sources(operation)
      end

      def response_sources(operation)
        operation.responses.flat_map do |code, response|
          fields_with_meaning(response.fields).map do |field|
            [field, "поле «#{field.path}» в ответе #{code} операции #{where(operation)}"]
          end
        end
      end

      def request_sources(operation)
        fields_with_meaning(operation.request_fields).map do |field|
          [field, "поле «#{field.path}» в теле запроса операции #{where(operation)}"]
        end
      end

      def fields_with_meaning(fields)
        @meanings.flatten(fields).select do |field|
          field.enum.is_a?(Array) && status_field?(field)
        end
      end

      def status_field?(field)
        found = @meanings.find([field], :status, deep: false)
        !found.nil?
      end

      def record(found, field, where)
        field.enum.each { |value| found[value.to_s] ||= where }
      end

      def mapping(value, where)
        canonical, kind = translate(value)
        StatusMapping.new(
          provider_value: value, canonical: canonical,
          verdict: kind == :exact ? :confident : :needs_confirmation,
          evidence: [evidence(value, where, canonical, kind)]
        )
      end

      # Точное совпадение — уверенно. Совпадение по части слова — с пометкой:
      # «sent» и «settled» начинаются одинаково, но означают разное.
      def translate(value)
        normalized = normalize(value)
        exact = @dictionary.find do |_canonical, values|
          values.any? { |value| normalize(value) == normalized }
        end
        return [exact.first.to_sym, :exact] if exact

        partial = @dictionary.find { |_canonical, values| Text.find([normalized], values) }
        partial ? [partial.first.to_sym, :partial] : [nil, :missing]
      end

      def normalize(value) = value.to_s.downcase.gsub(/[^[:alnum:]]+/, "_")

      def evidence(value, where, canonical, kind)
        Evidence.new(signal: :lexicon, weight: 0.0, detail: detail(value, where, canonical, kind))
      end

      def detail(value, where, canonical, kind)
        case kind
        when :exact then "«#{value}» найдено в словаре как «#{canonical}»; источник: #{where}"
        when :partial then "«#{value}» совпало со словарём частично, принято за «#{canonical}»; " \
                           "проверьте перевод. Источник: #{where}"
        else "«#{value}» в словаре не найдено, перевод не выбран; источник: #{where}"
        end
      end

      def where(operation) = "#{operation.http_method.to_s.upcase} #{operation.path}"
    end
  end
end
