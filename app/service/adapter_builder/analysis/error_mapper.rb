# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # HTTP-коды операций → коды ошибок контракта и действия. Берём и то, что
      # описал провайдер, и общий словарь: провайдер редко перечисляет 5xx, но
      # получить их обёртка обязана.
      class ErrorMapper
        # @param rules [Ports::Rules] словарь кодов ошибок
        def initialize(rules)
          @rules = rules
        end

        # @param operations [Array<Models::ApiOperation, nil>] операции занятых ролей
        # @return [Hash{Integer => Hash}] код ответа → { code:, action:, symbol:, described: }
        def call(operations)
          described = operations.compact.flat_map(&:error_codes).uniq
          (described | @rules.known_error_codes).sort.to_h do |code|
            [code, @rules.error_for(code).merge(described: described.include?(code))]
          end
        end
      end
    end
  end
end
