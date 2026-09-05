# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Parsing
      # Поиск свойства в схеме по регуляркам имени. Ответы у провайдеров бывают
      # завёрнуты в конверт (data/meta у KassaBox), поэтому ищем в глубину и
      # возвращаем путь целиком — по нему обёртка достанет значение через dig.
      class SchemaProbe
        Found = Struct.new(:path, :node, keyword_init: true) do
          # @return [Array<String>] значения enum найденного свойства
          def values
            Array(node[:enum]).map(&:to_s)
          end
        end

        MAX_DEPTH = 3

        # @param schema [Hash, nil] схема, в которой ищем
        def initialize(schema)
          @schema = schema || {}
        end

        # Первое подходящее свойство: сначала ближе к корню, потом глубже.
        # @param patterns [Array<Regexp>] чем узнаём имя свойства
        # @param with_enum [Boolean] брать только свойства с перечислением значений
        # @return [Found, nil]
        def find(patterns, with_enum: false)
          (0..MAX_DEPTH).each do |depth|
            found = walk(@schema, [], depth)
                    .find { |candidate| suits?(candidate, patterns, with_enum) }
            return found if found
          end
          nil
        end

        # Все свойства с перечислением значений — из них собирается карта статусов.
        # @return [Array<Found>]
        def enums
          levels = (0..MAX_DEPTH).flat_map { |depth| walk(@schema, [], depth) }
          levels.select { |found| found.values.any? }
        end

        private

        # @param candidate [Found]
        # @param patterns [Array<Regexp>]
        # @param with_enum [Boolean]
        # @return [Boolean] сравнивается последний сегмент пути, то есть имя свойства
        def suits?(candidate, patterns, with_enum)
          return false if with_enum && candidate.values.empty?

          patterns.any? { |pattern| pattern.match?(candidate.path.last) }
        end

        # Все свойства ровно на заданной глубине — обход послойный, чтобы близкое к корню
        # поле выигрывало у одноимённого вложенного.
        # @param node [Hash] узел схемы
        # @param path [Array<String>] путь до узла от корня
        # @param depth [Integer] сколько уровней осталось спуститься
        # @return [Array<Found>]
        def walk(node, path, depth)
          properties = properties_of(node)
          return [] if properties.nil?

          properties.flat_map do |name, property|
            current = path + [name.to_s]
            next walk(property, current, depth - 1) unless depth.zero?

            [Found.new(path: current, node: property)]
          end
        end

        # Массив прозрачен для поиска: свойства лежат в описании его элемента.
        # @param node [Object]
        # @return [Hash, nil] свойства узла или nil, если их нет
        def properties_of(node)
          return nil unless node.is_a?(Hash)

          node = node[:items] if node[:type].to_s == "array" && node[:items].is_a?(Hash)
          node[:properties] if node.is_a?(Hash) && node[:properties].is_a?(Hash)
        end
      end
    end
  end
end
