# frozen_string_literal: true

require_relative "evidence"
require_relative "meanings"
require_relative "result"

module Rsocket
  module Classify
    # В чём передаётся сумма: в копейках или дробным числом.
    #
    # Самая дорогая ошибка подключения: перепутав единицы, интеграция уйдёт в
    # бой и переведёт в сто раз больше или меньше, причём тесты этого не
    # заметят. Поэтому решение принимается по совокупности признаков — тип поля,
    # слова в описании, порядок величины минимума и примера — и всегда едет в
    # отчёт с обоснованием.
    class MoneyDetector
      INTEGER_TYPES = %w[integer].freeze
      FRACTIONAL_TYPES = %w[number float double].freeze

      NO_FIELD = "поле суммы в описании не найдено, единицы определить не по чему"

      def initialize(context)
        @spec = context.spec
        @meanings = Meanings.new(context.dictionaries.fields)
        @dictionary = context.dictionaries.money
        @weights = context.dictionaries.weights["money"] || {}
      end

      def call
        field = amount_field
        return MoneyDecision.new(evidence: [evidence(NO_FIELD)]) if field.nil?

        found = signals(field)
        MoneyDecision.new(unit: decide(found), field_path: field.path, evidence: found.map(&:last))
      end

      private

      # Сумму ищем там, где её отправляем: в теле запроса. Поля-объекты
      # пропускаем — единицы у скалярного значения, а не у конверта вокруг него.
      def amount_field
        @spec.operations.filter_map { |operation| scalar_amount(operation.request_fields) }.first
      end

      def scalar_amount(fields)
        @meanings.flatten(fields).find do |field|
          field.children.empty? && field.item.nil? && amount?(field)
        end
      end

      def amount?(field) = !@meanings.find([field], :amount, deep: false).nil?

      def signals(field)
        [*words_signals(field), type_signal(field), bound_signal(field)].compact
      end

      def decide(found)
        totals = totals_of(found)
        best = totals.max_by { |_unit, weight| weight }
        return if best.nil? || tie?(totals, best) || best.last < minimum_weight

        best.first
      end

      def minimum_weight = weight("minimum_weight")

      def totals_of(found)
        found.group_by(&:first).transform_values do |group|
          group.sum { |item| item.last.weight }
        end
      end

      def tie?(totals, best) = totals.count { |_unit, weight| weight == best.last } > 1

      # Слова обеих сторон собираются вместе, а не по первому попаданию: описание
      # «рубли и копейки через точку» содержит и то, и другое, и выбор по первому
      # совпадению дал бы копейки там, где на самом деле дробное число.
      def words_signals(field)
        text = field.description.to_s.downcase
        return [] if text.empty?

        [words_signal(text, :minor, "minor_words"), words_signal(text, :decimal, "decimal_words")]
      end

      def words_signal(text, unit, list)
        word = Array(@dictionary[list]).find { |candidate| text.include?(candidate) }
        return if word.nil?

        signal(unit, "words_in_description", "описание поля говорит «#{word}»")
      end

      def type_signal(field)
        return signal(:minor, "integer_type", "поле целочисленное") if integer?(field)
        return decimal_string_signal(field) if decimal_string?(field)
        return unless FRACTIONAL_TYPES.include?(field.type.to_s)

        signal(:decimal, "fractional_type", "поле дробное (#{field.type}#{format_of(field)})")
      end

      # Сумма строкой с точкой и копейками после неё — это рубли, как бы ни было
      # написано в описании: 1500.00 не бывает записью в минимальных единицах.
      def decimal_string?(field)
        return false unless field.type.to_s == "string"

        field.pattern.to_s.include?("\\.") || field.example.to_s.match?(/\A\d+\.\d+\z/)
      end

      def decimal_string_signal(field)
        where = if field.pattern.to_s.empty?
                  "пример «#{field.example}»"
                else
                  "шаблон «#{field.pattern}»"
                end
        signal(:decimal, "decimal_string_format",
               "сумма записана строкой с дробной частью: #{where}")
      end

      # Целое поле с крупным минимумом или примером: тысяча рублей никогда не
      # записывается числом 100000, а тысяча рублей в копейках — именно так.
      def bound_signal(field)
        return unless integer?(field)

        bound = large_bound(field)
        return if bound.nil?

        signal(:minor, "integer_with_large_bound", "#{bound.first} равен #{bound.last}")
      end

      def large_bound(field)
        minimum = @dictionary["integer_minimum_hint"]
        example = @dictionary["integer_example_hint"]
        return ["минимум", field.minimum] if minimum && field.minimum.to_f >= minimum
        return ["пример", field.example] if example && field.example.to_f >= example

        nil
      end

      def integer?(field) = INTEGER_TYPES.include?(field.type.to_s)

      def format_of(field) = field.format.nil? ? "" : ", #{field.format}"

      def signal(unit, weight_key, detail)
        [unit, Evidence.new(signal: :signature, weight: weight(weight_key), detail: detail)]
      end

      def weight(key) = (@weights[key] || 0.0).to_f

      def evidence(detail) = Evidence.new(signal: :signature, weight: 0.0, detail: detail)
    end
  end
end
