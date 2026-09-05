# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Rendering
      # Тестовые материалы в том виде, в каком они уходят в fixtures.json. Разделы
      # называются именами ролей контракта, поэтому файл сам подстраивается под
      # интерфейс: у одного контракта это create_request, у другого send_payout.
      class Fixtures
        # @param blueprint [Models::Blueprint] всё, что инструмент решил
        def initialize(blueprint)
          @blueprint = blueprint
          @fixtures = blueprint.fixtures
        end

        # @return [Hash{String => Object}] документ целиком; ключи строками — уходит в JSON
        def to_h
          calls.merge("callbacks" => callbacks, "statuses" => @blueprint.status_map)
        end

        private

        # @return [Hash] раздел на каждую роль, ходящую к провайдеру
        def calls
          @fixtures.calls.to_h { |role, item| [role.to_s, call(item)] }
        end

        # @param item [Analysis::FixturePlanner::Case]
        # @return [Hash] чем к эндпоинту обращаются и чем он отвечает
        def call(item)
          section = { "title" => item.title, "endpoint" => item.endpoint }
          section["request"] = item.request unless item.request.nil?
          section.merge("responses" => item.responses)
        end

        # Уведомление вместе с тем статусом, в который его переведёт обёртка: по
        # этой паре пишется тест на обработку колбэка.
        # @return [Hash] событие → пример тела и ожидаемый статус
        def callbacks
          @fixtures.callbacks.to_h do |item|
            [item.name, { "payload" => item.payload, "expected_operation_status" => item.expected }]
          end
        end
      end
    end
  end
end
