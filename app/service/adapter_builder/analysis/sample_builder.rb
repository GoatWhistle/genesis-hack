# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Схема провайдера → пример данных. Значения берём из самого описания:
      # сначала example, потом первое значение перечисления, потом границу, и
      # только если ничего этого нет — заглушку по типу. Выдумывать нельзя:
      # фикстура должна быть похожа на то, что провайдер действительно принимает.
      class SampleBuilder
        MAX_DEPTH = 4

        # Заглушки по формату строки — их провайдеры почти всегда описывают форматом,
        # а не примером.
        FORMATS = {
          "date-time" => "2026-01-01T12:00:00Z", "date" => "2026-01-01",
          "uuid" => "3f2504e0-4f89-41d3-9a0c-0305e82c3301", "email" => "user@example.com"
        }.freeze

        # @param schema [Hash, nil] схема с уже раскрытыми ссылками
        # @param overrides [Hash{Array<String> => Object}] путь до поля → нужное значение
        # @return [Hash, nil] пример объекта; nil, если схема не описывает объект
        def call(schema, overrides: {})
          sample = build(schema, 0)
          return nil unless sample.is_a?(Hash)

          overrides.each { |path, value| assign(sample, Array(path), value) }
          sample
        end

        private

        # @param node [Object] узел схемы
        # @param depth [Integer]
        # @return [Object, nil] значение для этого узла
        def build(node, depth)
          return nil unless node.is_a?(Hash)
          return nil if depth > MAX_DEPTH
          return node[:example] if node.key?(:example)

          enumerated = Array(node[:enum])
          return enumerated.first unless enumerated.empty?

          scalar(node, depth)
        end

        # @param node [Hash]
        # @param depth [Integer]
        # @return [Object, nil]
        def scalar(node, depth)
          case node[:type].to_s
          when "object" then object(node, depth)
          when "array" then [build(node[:items], depth + 1)].compact
          else simple(node, depth)
          end
        end

        # Тип без вложенности. Границу из схемы предпочитаем выдуманному числу:
        # она заведомо проходит проверки провайдера.
        # @param node [Hash]
        # @param depth [Integer]
        # @return [Object, nil]
        def simple(node, depth)
          case node[:type].to_s
          when "integer" then node[:minimum] || 1
          when "number" then node[:minimum] || 1.0
          when "boolean" then true
          when "string" then string(node)
          else untyped(node, depth)
          end
        end

        # Тип провайдер указывает не всегда: если у узла есть свойства, это объект.
        # @param node [Hash]
        # @param depth [Integer]
        # @return [Hash, nil]
        def untyped(node, depth)
          node[:properties].is_a?(Hash) ? object(node, depth) : nil
        end

        # Свойства раскрываем поштучно. Имена ключей делаем строками: пример уходит
        # в JSON, и ключи там такие, как их назвал провайдер.
        # @param node [Hash]
        # @param depth [Integer]
        # @return [Hash]
        def object(node, depth)
          properties = node[:properties]
          return {} unless properties.is_a?(Hash)

          properties.each_with_object({}) do |(name, property), sample|
            value = build(property, depth + 1)
            sample[name.to_s] = value unless value.nil?
          end
        end

        # @param node [Hash]
        # @return [String] по формату, а без формата — заметная заглушка
        def string(node)
          FORMATS.fetch(node[:format].to_s, "example")
        end

        # Значение подставляем только туда, где такое поле есть: иначе пример
        # перестанет соответствовать схеме провайдера.
        # @param sample [Hash] уже собранный пример
        # @param path [Array<String>] путь до поля
        # @param value [Object]
        # @return [void]
        def assign(sample, path, value)
          *head, last = path
          target = head.reduce(sample) { |node, key| node.is_a?(Hash) ? node[key] : nil }
          target[last] = value if target.is_a?(Hash) && target.key?(last)
        end
      end
    end
  end
end
