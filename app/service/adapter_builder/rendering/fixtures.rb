# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Rendering
      # Документ fixtures.json. Разделы названы именами ролей контракта.
      class Fixtures
        # @param blueprint [Models::Blueprint] всё, что инструмент решил
        def initialize(blueprint)
          @blueprint = blueprint
          @fixtures = blueprint.fixtures
        end

        # @return [Hash{String => Object}] документ целиком; ключи строками для печати в JSON
        def to_h
          calls.merge("callbacks" => callbacks, "statuses" => @blueprint.status_map)
        end

        private

        # @return [Hash] по разделу на каждую роль, обращающуюся к провайдеру
        def calls
          @fixtures.calls.to_h { |role, item| [role.to_s, call(item)] }
        end

        # @param item [Analysis::FixturePlanner::Case]
        # @return [Hash] запрос к эндпоинту и его ответы
        def call(item)
          section = { "title" => item.title, "endpoint" => item.endpoint }
          section["request"] = item.request unless item.request.nil?
          section.merge("responses" => item.responses)
        end

        # Уведомление и статус, в который его переводит собранный класс.
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
