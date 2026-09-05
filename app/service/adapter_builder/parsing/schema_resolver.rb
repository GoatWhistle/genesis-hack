# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Parsing
      # Приведение схемы OpenAPI к плоскому виду: раскрывает $ref и сводит составные
      # схемы к одной. Для правил важен набор полей, а не то, из скольких частей его
      # собрали, поэтому разбор документа этой возни не видит.
      class SchemaResolver
        MAX_DEPTH = 12

        # @param document [Hash] описание целиком — по нему разрешаются локальные $ref
        def initialize(document)
          @document = document
        end

        # Приводит схему к плоскому виду. Глубину считаем сами: описание может ссылаться
        # само на себя, и без предела разбор не закончится.
        # @param node [Hash, nil] узел описания
        # @param depth [Integer] текущая глубина раскрытия
        # @return [Hash, nil] узел без $ref и составных схем
        def call(node, depth = 0)
          return node unless node.is_a?(Hash)
          return node if depth > MAX_DEPTH

          node = call(dereference(node[:$ref]), depth + 1) if node.key?(:$ref)
          return node unless node.is_a?(Hash)

          combined(node, depth) || own_properties(node, depth)
        end

        private

        # allOf, oneOf и anyOf — три способа собрать схему из частей, и склеиваются
        # они по-разному, поэтому разбираются по отдельности.
        # @param node [Hash]
        # @param depth [Integer]
        # @return [Hash, nil] nil, если узел не составной
        def combined(node, depth)
          return merge_all_of(node, depth) if node.key?(:allOf)
          return pick_variant(node, depth) if node.key?(:oneOf) || node.key?(:anyOf)

          nil
        end

        # Свойства объекта раскрываем поштучно: ссылка может стоять на любом из них.
        # @param node [Hash]
        # @param depth [Integer]
        # @return [Hash]
        def own_properties(node, depth)
          return node unless node.key?(:properties)

          resolved = (node[:properties] || {}).transform_values { |value| call(value, depth + 1) }
          node.merge(properties: resolved)
        end

        # allOf собирает объект из частей: свойства и required объединяем, всё
        # остальное перекрывает более поздняя часть.
        # @param node [Hash] узел с ключом allOf
        # @param depth [Integer]
        # @return [Hash]
        def merge_all_of(node, depth)
          parts = node[:allOf].filter_map { |part| call(part, depth + 1) }
          merged = parts.reduce({}) do |acc, part|
            acc.merge(part) { |key, left, right| merge_values(key, left, right) }
          end
          call(node.except(:allOf).merge(merged) { |_, left, right| right || left }, depth + 1)
        end

        # @param key [Symbol] ключ, по которому столкнулись части allOf
        # @param left [Object] значение из ранней части
        # @param right [Object] значение из поздней части
        # @return [Object]
        def merge_values(key, left, right)
          return left.merge(right) if key == :properties
          return Array(left) | Array(right) if key == :required

          right
        end

        # oneOf/anyOf — взаимоисключающие способы заполнить объект (счёт или карта у
        # получателя). Склеивать их нельзя, поэтому берём первый вариант и отмечаем,
        # сколько их было: остальное уйдёт в предупреждения отчёта.
        # @param node [Hash] узел с ключом oneOf или anyOf
        # @param depth [Integer]
        # @return [Hash] первый вариант плюс ключ variants со счётчиком вариантов
        def pick_variant(node, depth)
          variants = node[:oneOf] || node[:anyOf]
          chosen = call(variants.first, depth + 1) || {}
          node.except(:oneOf, :anyOf).merge(chosen).merge(variants: variants.size)
        end

        # @param reference [String, nil] ссылка вида #/components/schemas/Payout
        # @return [Hash, nil] nil для внешних ссылок и несуществующих путей
        def dereference(reference)
          return nil unless reference.to_s.start_with?("#/")

          keys = reference.to_s.delete_prefix("#/").split("/").map(&:to_sym)
          keys.reduce(@document) { |node, key| node.is_a?(Hash) ? node[key] : nil }
        end
      end
    end
  end
end
