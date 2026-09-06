# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Ограничения для check_conditions: единицы суммы, границы, список валют.
      class ConstraintMiner
        Result = Struct.new(:constraints, :multiplier, :amount_expression, :notes,
                            keyword_init: true)

        # Ключ схемы → вид ограничения и сравнение для проверки.
        SCHEMA_BOUNDS = [%i[minimum min_amount less_than],
                         %i[maximum max_amount greater_than]].freeze

        # @param rules [Ports::Rules] словарь полей и секция constraints конфигурации
        def initialize(rules)
          @rules = rules
          @settings = rules.constraints
          @factory = ConstraintFactory.new(rules)
        end

        # @param operation [Models::ApiOperation, nil] операция создания
        # @param spec_text [String] название и описание API: границы могут быть указаны текстом
        # @return [Result] пустой набор с множителем 1, если операция не найдена
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

        # @return [Result] для случая, когда роль создания не занята
        def empty
          Result.new(constraints: [], multiplier: 1,
                     amount_expression: @settings.dig(:rendering, :number), notes: [])
        end

        # Сумма бывает во вложенном объекте (sum: { value, currency }).
        # @param operation [Models::ApiOperation]
        # @return [Parsing::SchemaProbe::Found, nil] числовое поле суммы
        def amount_property(operation)
          patterns = @rules.entry_for(@rules.payload_fields, :amount)&.fetch(:patterns) || []
          found = Parsing::SchemaProbe.new(operation.request_schema).find(patterns)
          return nil if found.nil?
          return found unless found.node[:type].to_s == "object"

          Parsing::SchemaProbe.new(found.node).find(patterns) || found
        end

        # Копейки признаём только у целого поля: у строки те же слова описывают формат.
        # @param amount [Parsing::SchemaProbe::Found, nil]
        # @param operation [Models::ApiOperation]
        # @param spec_text [String]
        # @return [Boolean] ожидает ли провайдер сумму в минорных единицах
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
        # @return [Boolean] является ли поле целочисленным
        def integer?(amount) = amount.node[:type].to_s == "integer"

        # Строка с точкой в шаблоне означает формат «1500.00», без точки — значение как есть.
        # @param amount [Parsing::SchemaProbe::Found]
        # @return [Boolean]
        def decimal?(amount) = amount.node[:pattern].to_s.include?(".")

        # Границы: сначала схема, затем текст; значения приводятся к единицам контракта.
        # @param amount [Parsing::SchemaProbe::Found, nil]
        # @param operation [Models::ApiOperation]
        # @param multiplier [Integer]
        # @return [Array<Models::Constraint>] границы из схемы, дополненные найденными в тексте
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

        # Множитель к числу из текста не применяется: там сумма в основной валюте.
        # @param rule [Hash] правило поиска: pattern, comparison, kind
        # @param match [MatchData] совпадение с группой value
        # @return [Models::Constraint, nil] nil, если число не распознано
        def text_constraint(rule, match)
          value = match[:value].to_s.gsub(/\s+/, "").to_i
          return nil if value.zero?

          @factory.call(
            rule.fetch(:kind),
            value: value, comparison: rule.fetch(:comparison).to_sym,
            source: "текст описания: «#{match[0].strip}»"
          )
        end

        # Список валют берётся только из enum: он задаёт полный набор.
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
        # @return [Numeric] то же значение в единицах контракта
        def scale(value, multiplier)
          return value if multiplier == 1

          scaled = value.to_f / multiplier
          (scaled % 1).zero? ? scaled.to_i : scaled.round(2)
        end

        # @param amount [Parsing::SchemaProbe::Found, nil]
        # @param minor [Boolean]
        # @return [Array<String>] принятые решения о сумме для отчёта
        def notes(amount, minor)
          return ["поле суммы в схеме запроса не найдено — сумма уходит как есть"] if amount.nil?

          units = minor ? "копейки" : "рубли"
          ["сумма провайдера: #{amount.path.join(".")} (#{amount.node[:type]}), единицы: #{units}"]
        end
      end
    end
  end
end
