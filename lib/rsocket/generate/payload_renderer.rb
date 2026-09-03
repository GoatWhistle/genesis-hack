# frozen_string_literal: true

require_relative "field_matcher"

module Rsocket
  module Generate
    # Превращает план сборки тела запроса в исходный текст на Ruby.
    #
    # Отделено от плана намеренно: план отвечает на вопрос «откуда берётся
    # значение», рендерер — на вопрос «как это выглядит в коде». Их легко
    # менять по отдельности, и план можно проверить тестами, не читая
    # сгенерированные строки.
    class PayloadRenderer
      # Простое имя можно писать символом (`amount:`), всё остальное —
      # строкой в кавычках (`"x-partner-id":`). Спецификации встречаются
      # разные, и ломаться на дефисе в имени поля нельзя.
      SIMPLE_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

      SOURCES = {
        currency: "operation.currency",
        external_id: "operation.id"
      }.freeze

      AMOUNT_SOURCES = {
        minor: "to_minor_units(operation.amount)",
        decimal: "operation.amount",
        string_minor: "to_minor_units(operation.amount).to_s",
        string_decimal: "format_amount(operation.amount)"
      }.freeze

      def initialize(plan, amount_mode: :minor, indent: 8)
        @plan = plan
        @amount_mode = amount_mode
        @indent = indent
      end

      def call
        render_nodes(@plan.nodes, @indent)
      end

      # Необязательные поля, которые инструмент связать не смог. В тело они не
      # попадают, но человек о них узнаёт — из комментария над методом и из
      # отчёта.
      def skipped_optional
        @plan.manual_fields.reject { |path| required_manual.include?(path) }
      end

      private

      def render_nodes(nodes, indent)
        rendered = entries(nodes, indent + 2)
        lines = ["{"]
        rendered.each_with_index do |entry, index|
          entry.each { |line| lines << line }
          lines[-1] += "," unless index == rendered.size - 1
        end
        lines << "#{" " * indent}}"
        lines.join("\n")
      end

      # Каждое поле — список строк: сначала пометка о ручном заполнении, если
      # она нужна, потом сама пара «ключ: значение».
      def entries(nodes, indent)
        pad = " " * indent
        nodes.filter_map do |node|
          next if skip?(node)

          lines = []
          lines << "#{pad}# ЗАПОЛНИТЬ ВРУЧНУЮ: #{manual_hint(node)}" if node.source == :manual
          lines << "#{pad}#{key(node.name)} #{value(node, indent)}"
          lines
        end
      end

      def skip?(node)
        node.source == :manual && !node.required
      end

      def value(node, indent)
        case node.source
        when :object then render_nodes(node.children, indent)
        when :requisite then "build_#{FieldMatcher.normalize(node.name)}(operation, request_method)"
        when :amount then amount_source
        when :manual then "nil"
        else SOURCES.fetch(node.source)
        end
      end

      def amount_source
        AMOUNT_SOURCES.fetch(@amount_mode)
      end

      def key(name)
        name.match?(SIMPLE_NAME) ? "#{name}:" : "#{name.inspect}:"
      end

      def manual_hint(node)
        node.description.to_s.strip.empty? ? "поле не связано с операцией" : node.description.strip
      end

      def required_manual
        @required_manual ||= collect_required_manual(@plan.nodes, "")
      end

      def collect_required_manual(nodes, prefix)
        nodes.flat_map do |node|
          path = prefix.empty? ? node.name : "#{prefix}.#{node.name}"
          next collect_required_manual(node.children, path) if node.object?

          node.source == :manual && node.required ? [path] : []
        end
      end
    end
  end
end
