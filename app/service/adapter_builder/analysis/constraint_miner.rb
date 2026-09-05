# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Ограничения для check_conditions: в каких единицах провайдер ждёт сумму,
      # какие границы у неё и какие валюты он принимает. Проверить эндпоинтом это
      # нельзя, поэтому читаем схему запроса и текст описания.
      class ConstraintMiner
        Result = Struct.new(:constraints, :multiplier, :amount_expression, :notes,
                            keyword_init: true)

        # Ключ схемы → вид ограничения и сравнение, которым его проверяют.
        SCHEMA_BOUNDS = [%i[minimum min_amount less_than],
                         %i[maximum max_amount greater_than]].freeze

        # @param rules [Ports::Rules] словарь полей и секция constraints конфига
        def initialize(rules)
          @rules = rules
          @settings = rules.constraints
          @factory = ConstraintFactory.new(rules)
        end

        # @param operation [Models::ApiOperation, nil] операция создания
        # @param spec_text [String] название и описание API — лимиты там называют словами
        # @return [Result] пустой набор без множителя, если операции нет
        def call(operation:, spec_text: "")
          return empty if operation.nil?

          amount = amount_property(operation)
          minor = minor_units?(amount, operation, spec_text)
          multiplier = minor ? @settings.fetch(:multiplier) : 1

          Result.new(constraints: constraints(amount, operation, multiplier),
                     multiplier: multiplier, notes: notes(amount, minor),
                     amount_expression: expression_for(amount, minor))
        end

        private

        # @param amount [Parsing::SchemaProbe::Found, nil] поле суммы в схеме запроса
        # @param operation [Models::ApiOperation]
        # @param multiplier [Integer] 1 или 100
        # @return [Array<Models::Constraint>] границы суммы и список валют
        def constraints(amount, operation, multiplier)
          amount_bounds(amount, operation, multiplier) + [currency_constraint(operation)].compact
        end

        # @return [Result] когда роль создания не распозналась
        def empty
          Result.new(constraints: [], multiplier: 1,
                     amount_expression: @settings.dig(:rendering, :number), notes: [])
        end

        # Сумма может лежать и в отдельном объекте (sum: { value, currency }),
        # поэтому, найдя объект, спускаемся в него за числовым полем.
        # @param operation [Models::ApiOperation]
        # @return [Parsing::SchemaProbe::Found, nil] числовое поле суммы
        def amount_property(operation)
          patterns = @rules.entry_for(@rules.payload_fields, :amount)&.fetch(:patterns) || []
          found = Parsing::SchemaProbe.new(operation.request_schema).find(patterns)
          return nil if found.nil?
          return found unless found.node[:type].to_s == "object"

          Parsing::SchemaProbe.new(found.node).find(patterns) || found
        end

        # Копейки признаём только у целого поля: у строковой суммы «рубли и копейки
        # через точку» те же слова описывают формат записи, а не единицы.
        # @param amount [Parsing::SchemaProbe::Found, nil]
        # @param operation [Models::ApiOperation]
        # @param spec_text [String]
        # @return [Boolean] ждёт ли провайдер сумму в копейках
        def minor_units?(amount, operation, spec_text)
          return false if amount.nil?
          return false if @settings.fetch(:minor_requires_integer) && !integer?(amount)

          text = [amount.node[:description], operation.text, spec_text].compact.join("\n")
          @settings.fetch(:minor_patterns).any? { |pattern| pattern.match?(text) }
        end

        # Чем обёртка печатает сумму: тип поля задаёт вид, единицы — множитель.
        # @param amount [Parsing::SchemaProbe::Found, nil]
        # @param minor [Boolean] сумма в копейках
        # @return [String] выражение на Ruby из шаблонов конфига
        def expression_for(amount, minor)
          rendering = @settings.fetch(:rendering)
          return rendering.fetch(:number) if amount.nil?

          case amount.node[:type].to_s
          when "integer" then rendering.fetch(minor ? :integer_minor : :integer_major)
          when "string" then rendering.fetch(decimal?(amount) ? :decimal_string : :string)
          else rendering.fetch(:number)
          end
        end

        # @param amount [Parsing::SchemaProbe::Found]
        # @return [Boolean] целое поле — единственное, у которого бывают копейки
        def integer?(amount) = amount.node[:type].to_s == "integer"

        # Строку с точкой в шаблоне провайдер ждёт как «1500.00», без точки — как есть.
        # @param amount [Parsing::SchemaProbe::Found]
        # @return [Boolean]
        def decimal?(amount) = amount.node[:pattern].to_s.include?(".")

        # Границы: сперва схема (провайдер обязан держать её актуальной), затем
        # текст описания. Значения приводим к единицам контракта заказчика.
        # @param amount [Parsing::SchemaProbe::Found, nil]
        # @param operation [Models::ApiOperation]
        # @param multiplier [Integer]
        # @return [Array<Models::Constraint>] границы из схемы, дополненные текстовыми
        def amount_bounds(amount, operation, multiplier)
          from_schema = schema_bounds(amount, multiplier)
          taken = from_schema.map(&:kind)
          from_text = text_bounds(operation, multiplier)
          from_schema + from_text.reject { |rule| taken.include?(rule.kind) }
        end

        # @param amount [Parsing::SchemaProbe::Found, nil]
        # @param multiplier [Integer]
        # @return [Array<Models::Constraint>] minimum и maximum поля суммы
        def schema_bounds(amount, multiplier)
          return [] if amount.nil?

          SCHEMA_BOUNDS.filter_map do |key, kind, comparison|
            value = amount.node[key]
            next if value.nil?

            @factory.call(kind, comparison: comparison, value: scale(value, multiplier),
                                source: "#{key} у поля #{amount.path.join(".")} в схеме запроса")
          end
        end

        # @param operation [Models::ApiOperation]
        # @param _multiplier [Integer] не используется, см. text_constraint
        # @return [Array<Models::Constraint>]
        def text_bounds(operation, _multiplier)
          @settings.fetch(:text_rules).filter_map do |rule|
            match = rule.fetch(:pattern).match(operation.text.to_s)
            text_constraint(rule, match) unless match.nil?
          end
        end

        # Множитель к найденному в тексте числу не применяем: в описании сумму
        # называют в валюте («минимальная сумма — 1000 RUB»), а не в копейках.
        # @param rule [Hash] правило поиска: pattern, comparison, kind
        # @param match [MatchData] совпадение с группой value
        # @return [Models::Constraint, nil] nil, если число не разобралось
        def text_constraint(rule, match)
          value = match[:value].to_s.gsub(/\s+/, "").to_i
          return nil if value.zero?

          @factory.call(
            rule.fetch(:kind),
            value: value, comparison: rule.fetch(:comparison).to_sym,
            source: "текст описания: «#{match[0].strip}»"
          )
        end

        # Список валют берём только из enum: перечисление в схеме — обязательство провайдера,
        # а валюта, названная в тексте, ещё не значит, что других он не примет.
        # @param operation [Models::ApiOperation]
        # @return [Models::Constraint, nil]
        def currency_constraint(operation)
          patterns = @rules.entry_for(@rules.payload_fields, :currency)&.fetch(:patterns) || []
          found = Parsing::SchemaProbe.new(operation.request_schema).find(patterns, with_enum: true)
          return nil if found.nil?

          @factory.call(
            Models::Constraint::CURRENCY,
            value: found.values, source: "enum поля #{found.path.join(".")} в схеме запроса"
          )
        end

        # @param value [Numeric] граница в единицах провайдера
        # @param multiplier [Integer]
        # @return [Numeric] она же в единицах контракта заказчика
        def scale(value, multiplier)
          return value if multiplier == 1

          scaled = value.to_f / multiplier
          (scaled % 1).zero? ? scaled.to_i : scaled.round(2)
        end

        # @param amount [Parsing::SchemaProbe::Found, nil]
        # @param minor [Boolean]
        # @return [Array<String>] что инструмент решил про сумму — для проверки человеком
        def notes(amount, minor)
          return ["поле суммы в схеме запроса не найдено — сумма уходит как есть"] if amount.nil?

          units = minor ? "копейки" : "рубли"
          ["сумма провайдера: #{amount.path.join(".")} (#{amount.node[:type]}), единицы: #{units}"]
        end
      end
    end
  end
end
