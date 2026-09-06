# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Classification
      # Связь операций между собой: статус и отмена обязаны относиться к тому же
      # переводу, который создаёт create-операция. Проверка структурная — по ресурсу
      # в адресе, параметру идентификатора и схемам, а не по одному общему слову.
      module Coherence
        # Слова, которые есть почти в каждом платёжном API: общий префикс из них
        # доказательством связи не считается.
        GENERIC = %w[api rest public open payment pay transaction operation request order
                     resource merchant account service post get put patch delete create update
                     list new fetch retrieve details info].freeze

        # Номер версии в адресе: /v1, /v2024 — доказательством связи не считается.
        VERSION = /\Av\d+\z/

        # Последний сегмент адреса, означающий действие, а не ресурс: у RPC-подобных
        # API соседние действия одного раздела и есть создание со статусом.
        ACTIONS = %w[create get status details detail info retrieve fetch cancel submit execute
                     update list new process send].freeze

        # Сколько очков нужно набрать, чтобы считать операции связанными.
        REQUIRED = 3

        # Сколько свойств должно совпасть у ответов, чтобы это считалось доказательством.
        SHARED_PROPERTIES = 3

        # Глубина обхода схемы при сборе имён свойств.
        DEPTH = 2

        module_function

        # @param create [Models::ApiOperation] операция создания выплаты
        # @param other [Models::ApiOperation] кандидат на статус или отмену
        # @return [Boolean] доказана ли связь
        def linked?(create, other)
          points(evidence(create, other)) >= REQUIRED
        end

        # @param create [Models::ApiOperation]
        # @param other [Models::ApiOperation]
        # @return [Hash{Symbol => Integer}] доказательства связи и их вес
        def evidence(create, other)
          return {} if create.nil? || other.nil? || create.equal?(other)

          {
            resource: resource_points(create, other),
            path: path_points(create, other),
            identifier: identifier_points(create, other),
            schema: schema_points(create, other)
          }.reject { |_, weight| weight.zero? }
        end

        # @param found [Hash{Symbol => Integer}]
        # @return [Integer] очки; без ресурса и адреса связь не признаётся
        def points(found)
          return 0 if found[:resource].to_i < 2 && found[:path].to_i.zero?

          found.values.sum
        end

        # @return [String] доказательства словами, для отчёта
        def explain(create, other)
          found = evidence(create, other)
          return "связь не подтверждена" if found.empty?

          found.keys.join(", ")
        end

        # Совпало значимое слово ресурса — payout, ach, wire; общее слово вроде
        # payment даёт вдвое меньше и само по себе связь не доказывает.
        # @return [Integer]
        def resource_points(create, other)
          shared = tokens(create) & tokens(other)
          return 2 if shared.any? { |token| !GENERIC.include?(token) && !VERSION.match?(token) }

          shared.empty? ? 0 : 1
        end

        # Адрес статуса — это адрес создания плюс идентификатор, либо тот же
        # раздел с другим действием на конце: /payments/create и /payments/get.
        # @return [Integer]
        def path_points(create, other)
          return 2 if nested?(create.path, other.path) || nested?(other.path, create.path)

          same_branch?(segments(create.path), segments(other.path)) ? 2 : 0
        end

        # @param left [Array<String>] статические сегменты адреса создания
        # @param right [Array<String>] статические сегменты адреса кандидата
        # @return [Boolean] адреса ведут в один раздел описания
        def same_branch?(left, right)
          return false if left.empty? || right.empty?

          left == right || prefix?(left, right) || prefix?(right, left) || sibling?(left, right)
        end

        # Адрес статуса — это адрес создания плюс идентификатор: сравниваются
        # шаблоны как есть, вместе с параметрами, иначе теряются адреса, у которых
        # весь путь состоит из подстановок.
        # @param outer [String]
        # @param inner [String]
        # @return [Boolean]
        def nested?(outer, inner)
          outer.to_s.start_with?("#{inner}/") && !inner.to_s.empty? && inner.to_s != "/"
        end

        # Соседние действия одного раздела: /payments/create и /payments/get.
        # @param left [Array<String>]
        # @param right [Array<String>]
        # @return [Boolean]
        def sibling?(left, right)
          return false unless left.size == right.size && left[0..-2] == right[0..-2]

          ACTIONS.include?(left.last) && ACTIONS.include?(right.last)
        end

        # Статус и отмена обращаются к одной операции по её идентификатору.
        # @return [Integer]
        def identifier_points(create, other)
          parameter = other.path_parameters.map { |item| item[:name].to_s }.last
          return 0 if parameter.nil?

          words = normalize(parameter)
          return 1 if words.intersect?(tokens(create))
          return 1 if response_properties(create).any? { |name| normalize(name) == words }

          0
        end

        # @return [Integer] ответы описывают один и тот же объект
        def schema_points(create, other)
          shared = response_properties(create) & response_properties(other)
          shared.size >= SHARED_PROPERTIES ? 1 : 0
        end

        # @param outer [Array<String>]
        # @param inner [Array<String>]
        # @return [Boolean] один список статических сегментов начинает другой
        def prefix?(outer, inner)
          return false if inner.empty? || outer.size <= inner.size

          outer.first(inner.size) == inner
        end

        # @param path [String]
        # @return [Array<String>] статические сегменты адреса, приведённые к основе
        def segments(path)
          path.to_s.split("/").reject { |part| part.empty? || part.start_with?("{") }
              .map { |part| singular(part.downcase) }
        end

        # Слова операции: два последних сегмента адреса и operationId. Начало адреса
        # у всех операций провайдера общее и о переводе ничего не говорит, а имя
        # операции без operationId — это тот же адрес целиком.
        # @param operation [Models::ApiOperation]
        # @return [Array<String>]
        def tokens(operation)
          (segments(operation.path).last(2) + normalize(operation.operation_id)).uniq
        end

        # @param value [String]
        # @return [Array<String>] слова длиннее двух букв в единственном числе
        def normalize(value)
          value.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.split(/[^a-z0-9]+/)
               .reject { |word| word.length < 3 }.map { |word| singular(word) }
        end

        # @param word [String]
        # @return [String]
        def singular(word)
          return word.sub(/ies\z/, "y") if word.end_with?("ies")
          return word.chomp("es") if word.end_with?("ses", "xes", "ches")
          return word.chomp("s") if word.end_with?("s") && !word.end_with?("ss")

          word
        end

        # @param operation [Models::ApiOperation]
        # @return [Array<String>] имена свойств успешного ответа
        def response_properties(operation)
          schema = operation.success_response&.dig(:schema)
          property_names(schema)
        end

        # @param schema [Hash, nil]
        # @param depth [Integer]
        # @return [Array<String>]
        def property_names(schema, depth = 0)
          return [] unless schema.is_a?(Hash) && depth < DEPTH

          own = schema[:properties].is_a?(Hash) ? schema[:properties] : {}
          own.keys.map(&:to_s) +
            own.values.flat_map { |value| property_names(value, depth + 1) } +
            property_names(schema[:items], depth + 1)
        end
      end
    end
  end
end
