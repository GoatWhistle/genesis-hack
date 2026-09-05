# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Перевод состояний провайдера в статусы контракта заказчика. Значения берём
      # из enum в схемах ответов, а не из текста: перечисление — единственное место,
      # где провайдер обязан перечислить состояния полностью.
      class StatusMapper
        Result = Struct.new(:status_map, :event_map, :status_path, :unmapped, keyword_init: true)

        # @param rules [Ports::Rules] шаблоны статусов и полей webhook
        def initialize(rules)
          @rules = rules
        end

        # @param operations [Array<Models::ApiOperation, nil>] операции занятых ролей
        # @param callback_schema [Hash, nil] схема тела webhook
        # @return [Result] карты статусов и событий, путь до статуса и непереведённые состояния
        def call(operations:, callback_schema: nil)
          found = status_property(operations)
          tokens = found ? found.values : []
          tokens |= collected_tokens(operations)

          Result.new(
            status_map: translate(tokens),
            event_map: event_map(callback_schema),
            status_path: found&.path || ["status"],
            unmapped: tokens.reject { |token| @rules.contract_status(token) }
          )
        end

        private

        # @param operations [Array<Models::ApiOperation, nil>]
        # @return [Parsing::SchemaProbe::Found, nil] поле статуса с перечислением значений
        def status_property(operations)
          operations.compact.filter_map do |operation|
            Parsing::SchemaProbe.new(operation.success_response&.dig(:schema)).find(
              @rules.callback_fields.fetch(:status), with_enum: true
            )
          end.first
        end

        # Подстраховка: если у статус-запроса перечисления нет, собираем состояния
        # из всех ответов операций, попавших в роли.
        # @param operations [Array<Models::ApiOperation, nil>]
        # @return [Array<String>] состояния из всех ответов, включая ошибочные
        def collected_tokens(operations)
          responses = operations.compact.flat_map { |operation| operation.responses.values }
          responses.flat_map { |response| status_enums(response[:schema]) }.uniq
        end

        # @param schema [Hash, nil]
        # @return [Array<String>] значения enum у полей, похожих на статус
        def status_enums(schema)
          patterns = @rules.callback_fields.fetch(:status)
          found = Parsing::SchemaProbe.new(schema).enums.select do |candidate|
            patterns.any? { |pattern| pattern.match?(candidate.path.last) }
          end
          found.flat_map(&:values)
        end

        # @param tokens [Array<String>] состояния провайдера
        # @return [Hash{String => String}] непереводимые состояния в карту не попадают
        def translate(tokens)
          tokens.to_h { |token| [token, @rules.contract_status(token)] }.compact
        end

        # События webhook вида payout.completed переводим по последнему сегменту:
        # именно он несёт состояние, префикс лишь называет объект.
        # @param callback_schema [Hash, nil]
        # @return [Hash{String => String}] событие webhook → статус контракта
        def event_map(callback_schema)
          return {} if callback_schema.nil?

          patterns = @rules.callback_fields.fetch(:event)
          found = Parsing::SchemaProbe.new(callback_schema).find(patterns, with_enum: true)
          return {} if found.nil?

          found.values.to_h do |event|
            [event, @rules.contract_status(event.split(/[.\-_:]/).last)]
          end.compact
        end
      end
    end
  end
end
