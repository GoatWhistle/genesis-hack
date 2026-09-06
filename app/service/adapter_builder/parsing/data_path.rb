# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Parsing
      # Типизированный путь в JSON. Массив допустим только с одним элементом:
      # без ключа выбора нельзя утверждать, что первая запись — нужный платёж.
      module DataPath
        module_function

        def read(body, path)
          Array(path).reduce(body) { |node, key| child(node, key) }
        end

        def child(node, key)
          case node
          when Hash
            actual = [key, key.to_s, key.to_s.to_sym].find { |candidate| node.key?(candidate) }
            node[actual] unless actual.nil?
          when Array then node[key] if single_index?(node, key)
          end
        end

        def single_index?(node, key)
          key.is_a?(Integer) && key.zero? && node.one?
        end

        def assign(body, path, value)
          *head, last = path
          target = read(body, head)
          case target
          when Hash
            key = [last, last.to_s, last.to_s.to_sym].find { |candidate| target.key?(candidate) }
            target[key] = value unless key.nil?
          when Array then target[last] = value if single_index?(target, last)
          end
        end
      end
    end
  end
end
