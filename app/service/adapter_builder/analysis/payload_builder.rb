# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Сборка тела запроса: свойству схемы сопоставляется выражение из словаря.
      class PayloadBuilder
        Field = Struct.new(:name, :source, :required, :children, :matched, keyword_init: true) do
          # @return [Boolean] поле без вложенных: печатается значением, а не хешем
          def leaf?
            children.nil?
          end
        end

        # Положение в схеме: путь от корня, текущая глубина и словарь, применяемый на этом уровне.
        Position = Struct.new(:path, :depth, :dictionary, keyword_init: true) do
          # @param name [String] свойство, в которое выполняется переход
          # @param dictionary [Array<Hash>] словарь для вложенного уровня
          # @return [Position]
          def deeper(name, dictionary)
            Position.new(path: path + [name], depth: depth + 1, dictionary: dictionary)
          end
        end

        Result = Struct.new(:fields, :headers, :warnings, keyword_init: true)

        MAX_DEPTH = 3

        # @param rules [Ports::Rules] словари полей тела и реквизитов
        def initialize(rules)
          @rules = rules
        end

        # @param operation [Models::ApiOperation, nil] операция, тело запроса которой собирается
        # @return [Result] поля тела, заголовки запроса и предупреждения
        def call(operation:)
          return Result.new(fields: [], headers: {}, warnings: []) if operation.nil?

          @warnings = []
          start = Position.new(path: [], depth: 0, dictionary: @rules.payload_fields)
          Result.new(fields: walk(operation.request_schema, start), warnings: @warnings,
                     headers: headers(operation))
        end

        private

        # @param schema [Hash, nil] схема объекта
        # @param position [Position] положение в схеме
        # @return [Array<Field>] поля этого уровня
        def walk(schema, position)
          properties = schema.is_a?(Hash) ? schema[:properties] : nil
          return [] unless properties.is_a?(Hash)

          required = Array(schema[:required]).map(&:to_s)
          properties.filter_map do |name, property|
            build(name.to_s, property, position, required.include?(name.to_s))
          end
        end

        # @param name [String] имя свойства у провайдера
        # @param property [Hash] его схема
        # @param position [Position]
        # @param required [Boolean] объявлено ли свойство обязательным
        # @return [Field, nil] nil, если поле необязательное и источник не найден
        def build(name, property, position, required)
          entry = @rules.field_for(position.dictionary, name)
          return nested(name, property, entry, position, required) if nest?(property, position)
          return leaf(name, entry, property, required) if entry&.dig(:source)

          unmatched(name, position.path + [name], required, entry)
        end

        # @param property [Hash]
        # @param position [Position]
        # @return [Boolean] выполнять ли переход внутрь; глубже MAX_DEPTH разбор не идёт
        def nest?(property, position)
          object?(property) && position.depth < MAX_DEPTH
        end

        # @param name [String]
        # @param entry [Hash] запись словаря с выражением-источником
        # @param property [Hash]
        # @param required [Boolean]
        # @return [Field]
        def leaf(name, entry, property, required)
          Field.new(name: name, source: source(entry, property), required: required,
                    matched: entry[:field])
        end

        # @param name [String]
        # @param property [Hash]
        # @param entry [Hash, nil] запись словаря для самого объекта
        # @param position [Position]
        # @param required [Boolean]
        # @return [Field, nil] объект без распознанных свойств считается незаполненным
        def nested(name, property, entry, position, required)
          inner = position.deeper(name, dictionary_for(entry))
          children = walk(property, inner)
          return unmatched(name, inner.path, required, entry) if children.empty?

          warn_about_variants(property, inner.path)
          Field.new(name: name, required: required, children: children, matched: entry&.dig(:field))
        end

        # Получатель разбирается словарём реквизитов, остальное — словарём тела.
        # @param entry [Hash, nil] запись словаря для объекта перехода
        # @return [Array<Hash>] словарь для свойств этого объекта
        def dictionary_for(entry)
          return @rules.requisite_fields if entry.nil? || entry[:field].to_s == "recipient"

          @rules.payload_fields
        end

        # Поле, собранное из oneOf: взят первый вариант, случай требует ручной проверки.
        # @param property [Hash]
        # @param path [Array<String>]
        # @return [void]
        def warn_about_variants(property, path)
          return unless property[:variants].to_i > 1

          @warnings << "поле #{path.join(".")} заполняется одним из " \
                       "#{property[:variants]} способов — взят первый, проверьте его"
        end

        # @param name [String]
        # @param path [Array<String>]
        # @param required [Boolean]
        # @param entry [Hash, nil]
        # @return [Field, nil] обязательное поле печатается с TODO, необязательное не печатается
        def unmatched(name, path, required, entry)
          return nil unless required

          @warnings << "поле #{path.join(".")} обязательно, но правила не знают, чем его заполнить"
          Field.new(name: name, source: nil, required: true, matched: entry&.dig(:field))
        end

        # У поля с enum первое значение идёт запасным.
        # @param entry [Hash] запись словаря
        # @param property [Hash] схема свойства
        # @return [String] выражение на Ruby
        def source(entry, property)
          values = Array(property[:enum])
          return entry[:source] if values.empty?

          "#{entry[:source]} || #{values.first.to_s.inspect}"
        end

        # @param property [Object]
        # @return [Boolean] объект узнаём и по типу, и по наличию свойств: тип пишут не всегда
        def object?(property)
          return false unless property.is_a?(Hash)

          property[:type].to_s == "object" || property[:properties].is_a?(Hash)
        end

        # Заголовки: правила узнают вид (идемпотентность, подпись), контракт даёт выражение.
        # @param operation [Models::ApiOperation]
        # @return [Hash{String => String}] имя заголовка у провайдера → выражение
        def headers(operation)
          operation.header_parameters.filter_map do |parameter|
            source = @rules.header_source(@rules.header_kind(parameter[:name]))
            [parameter[:name], source] unless source.nil?
          end.to_h
        end
      end
    end
  end
end
