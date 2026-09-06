# frozen_string_literal: true

require "uri"

module Service
  module AdapterBuilder
    module Testing
      # Заявка для вызова: значения берутся из ограничений, примера запроса и ответа.
      class Payment
        DEFAULT_AMOUNT = 1000
        DEFAULT_CURRENCY = "RUB"
        ID = "rsocket_check_1"
        PROVIDER_ID = "provider_check_1"
        DESCRIPTION = "проверка сборки rsocket"

        # @param blueprint [Models::Blueprint] всё, что инструмент решил
        def initialize(blueprint)
          @blueprint = blueprint
        end

        # @return [Hash] заявка в том виде, в каком её читает проба контракта
        def to_h
          { id: ID, amount: amount, currency: currency, requisite: requisite,
            provider_id: provider_id, description: DESCRIPTION }
        end

        # Совпадает с примером ответа на создание: по нему строится адрес статус-запроса.
        # @return [String]
        def provider_id
          return location_id if @blueprint.created_id_header

          value = dig(success_response(create_role), Array(@blueprint.created_id_field))
          value.nil? ? PROVIDER_ID : value.to_s
        end

        def location_id
          location = location_header
          path = URI.parse(location.to_s).path.to_s
          path.split("/").last&.gsub(/%[0-9a-f]{2}/i) do |byte|
            byte[1..].to_i(16).chr
          end || PROVIDER_ID
        rescue URI::InvalidURIError
          PROVIDER_ID
        end

        def location_header
          item = @blueprint.fixtures.calls[create_role]
          code = item.responses.keys.select { |key| key.start_with?("2") }.min
          item.response_headers&.dig(code, @blueprint.created_id_header.downcase)
        end

        # @param role [Symbol] роль контракта
        # @return [Hash, nil] пример успешного ответа этой роли
        def success_response(role)
          responses = @blueprint.fixtures.calls[role]&.responses.to_h
          code = responses.keys.min_by { |key| key.to_s.start_with?("2") ? key.to_i : 999 }
          responses[code] if code.to_s.start_with?("2")
        end

        # @return [Symbol, nil] роль, создающая операцию у провайдера
        def create_role
          binding = @blueprint.bindings.values.find do |item|
            item.bound? && item.role.trait?(:creates_operation)
          end
          binding&.role_name
        end

        private

        # Сумма в границах провайдера: используется минимум, объявленный допустимым.
        # @return [Integer, Float]
        def amount
          minimum = limit(:min_amount) || DEFAULT_AMOUNT
          maximum = limit(:max_amount)
          maximum && minimum > maximum ? maximum : minimum
        end

        # @return [String] валюта из списка провайдера
        def currency
          Array(limit(Models::Constraint::CURRENCY)).first || DEFAULT_CURRENCY
        end

        # Реквизиты берутся из примера запроса: там формат провайдера.
        # @return [Hash] раздел получателя из примера запроса
        def requisite
          request = @blueprint.fixtures.calls[create_role]&.request
          return {} unless request.is_a?(Hash)

          request.values.find { |value| value.is_a?(Hash) } || request
        end

        # @param kind [Symbol] вид ограничения
        # @return [Object, nil] значение ограничения, если оно найдено в описании
        def limit(kind)
          @blueprint.constraints.find { |constraint| constraint.kind == kind }&.value
        end

        # @param body [Hash, nil] тело примера
        # @param path [Array<String>] путь до значения
        # @return [Object, nil]
        def dig(body, path)
          Parsing::DataPath.read(body, path)
        end
      end
    end
  end
end
