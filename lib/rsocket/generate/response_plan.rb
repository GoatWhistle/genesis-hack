# frozen_string_literal: true

require_relative "field_matcher"

module Rsocket
  module Generate
    # Где в ответе провайдера лежат идентификатор выплаты, её статус и код
    # ошибки.
    #
    # Отдельная задача от сборки запроса, потому что ответ бывает завёрнут в
    # конверт: у одного провайдера статус лежит в `status`, у другого — в
    # `data.state`. Путь возвращается полным, поэтому конверт разбирается сам
    # собой и отдельной ветки в коде не требует.
    class ResponsePlan
      SUCCESS = (200..299)

      def initialize(operations, matcher: FieldMatcher.default)
        @matcher = matcher
        @operations = operations.compact
      end

      def id_path
        @id_path ||= first_path(success_leaves, :provider_id)
      end

      # Статусное поле ищется среди тех, у кого есть перечисление допустимых
      # значений: именно оно отличает настоящий статус от поля с похожим
      # именем.
      def status_path
        @status_path ||= first_path(success_leaves.select(&:enum), :status) ||
                         first_path(success_leaves, :status)
      end

      def error_code_path
        @error_code_path ||= first_path(error_leaves, :error_code)
      end

      # Значения статусов, объявленные провайдером. Основа карты статусов,
      # когда классификатор не дал своей.
      def provider_statuses
        leaf = success_leaves.find { |f| f.path == status_path&.join(".") }
        leaf&.enum || []
      end

      # Коды ответа с ошибкой, описанные в спецификации. Обрабатывать имеет
      # смысл ровно их: выдумывать обработку кода, которого провайдер не
      # объявлял, — значит писать мёртвый код.
      def error_codes
        @error_codes ||= @operations.flat_map { |op| op.responses.keys }.select { |c| c >= 400 }
                                    .uniq.sort
      end

      private

      def first_path(leaves, role)
        leaf = leaves.find { |field| @matcher.role?(field.name, role) }
        leaf && (leaf.path || leaf.name).split(".")
      end

      def success_leaves
        @success_leaves ||= leaves_of { |code| SUCCESS.cover?(code) }
      end

      def error_leaves
        @error_leaves ||= leaves_of { |code| code >= 400 }
      end

      def leaves_of(&selector)
        @operations.flat_map do |operation|
          operation.responses.select { |code, _| selector.call(code) }
                   .flat_map { |_, response| flatten(response.fields) }
        end
      end

      def flatten(fields)
        fields.flat_map { |field| field.children.any? ? flatten(field.children) : [field] }
      end
    end
  end
end
