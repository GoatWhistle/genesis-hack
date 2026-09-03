# frozen_string_literal: true

require_relative "evidence"
require_relative "meanings"
require_relative "result"
require_relative "text"

module Rsocket
  module Classify
    # Классы ошибок: что вызывающему коду делать при каждом отказе провайдера.
    #
    # Сначала код ответа — он есть всегда и врёт редко. Потом уточнение по коду
    # ошибки провайдера и словам в описании: 402 «insufficient_balance» стоит
    # повторить позже, а 402 «card_blocked» повторять бессмысленно.
    class ErrorMapper
      ERROR_CODES = (400..599)

      def initialize(context)
        @spec = context.spec
        @meanings = Meanings.new(context.dictionaries.fields)
        @dictionary = context.dictionaries.errors
      end

      def call
        (from_responses + from_catalogue).uniq { |mapping| key(mapping) }
      end

      private

      def key(mapping) = [mapping.http_code, mapping.provider_code]

      # По одному отображению на каждый код ответа: это тот минимум, который
      # готовый код обязан уметь обработать, даже если провайдер не описал ни
      # одного своего кода ошибки.
      def from_responses
        error_responses.map { |code, response| by_http_code(code, response) }
      end

      def error_responses
        @spec.operations
             .flat_map { |operation| operation.responses.to_a }
             .select { |code, _| code.is_a?(Integer) && ERROR_CODES.cover?(code) }
             .uniq(&:first)
             .sort_by(&:first)
      end

      def by_http_code(code, response)
        klass = klass_for_code(code)
        ErrorMapping.new(
          http_code: code, klass: klass,
          evidence: [evidence("код ответа #{code} отнесён словарём к классу «#{klass}»" \
                              "#{description(response)}")]
        )
      end

      def description(response)
        response.description.nil? ? "" : "; описание: «#{response.description.strip}»"
      end

      def klass_for_code(code)
        direct = @dictionary.dig("by_code", code.to_s)
        return direct.to_sym if direct

        range = Array(@dictionary["by_range"]).find do |rule|
          (rule["from"]..rule["to"]).cover?(code)
        end
        range ? range["class"].to_sym : nil
      end

      # Каталог кодов ошибок провайдера: перечисления в схемах ошибок. Это самая
      # ценная часть — именно по этим кодам готовый код принимает решение о
      # повторе.
      def from_catalogue
        catalogue.map { |code, where| by_provider_code(code, where) }
      end

      # Каталог собираем по всем ответам, а не только по отказам: причина
      # отказа часто перечислена внутри успешного ответа, рядом со статусом.
      def catalogue
        found = {}
        @spec.operations.each do |operation|
          catalogue_of(operation).each { |code, where| found[code] ||= where }
        end
        found.sort.to_h
      end

      def catalogue_of(operation)
        operation.responses.flat_map do |code, response|
          error_code_fields(response.fields).flat_map do |field|
            field.enum.map { |value| [value.to_s, "поле «#{field.path}» в ответе #{code}"] }
          end
        end
      end

      def error_code_fields(fields)
        @meanings.flatten(fields).select do |field|
          field.enum.is_a?(Array) && !@meanings.find([field], :error_code, deep: false).nil?
        end
      end

      def by_provider_code(code, where)
        klass, word = klass_for_words(code)
        ErrorMapping.new(
          provider_code: code, klass: klass,
          evidence: [evidence("#{detail(code, klass, word)}; источник: #{where}")]
        )
      end

      def detail(code, klass, word)
        return "код ошибки «#{code}» словарю не знаком, класс не выбран" if klass.nil?

        "код ошибки «#{code}» содержит «#{word}», это класс «#{klass}»"
      end

      def klass_for_words(code)
        tokens = Text.tokens(code) + [Text.tokens(code).join("_")]
        Array(@dictionary["by_words"]).each do |klass, words|
          word = Text.find(tokens, words)
          return [klass.to_sym, word] if word
        end
        [nil, nil]
      end

      def evidence(detail) = Evidence.new(signal: :lexicon, weight: 0.0, detail: detail)
    end
  end
end
