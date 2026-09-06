# frozen_string_literal: true

require "json"

module Service
  module AdapterBuilder
    module Testing
      # Проверка отправленного запроса: по возвращённому значению промах не виден.
      class Wire
        Check = Report::Check

        JSON_TYPE = "application/json"

        # @param blueprint [Models::Blueprint] запланированные запросы и схема авторизации
        def initialize(blueprint)
          @blueprint = blueprint
          @credentials = blueprint.credentials
        end

        # @param role [Symbol] роль контракта
        # @param route [StubServer::Route] адрес, по которому её ждали
        # @param received [StubServer::Received, nil] фактически полученный запрос
        # @return [Array<Check>] проверки по этому запросу
        def call(role:, route:, received:)
          return [missing(role, route)] if received.nil?

          [address(role, route, received), signature(role, received), body(role, received)].compact
        end

        private

        # @param role [Symbol]
        # @param route [StubServer::Route]
        # @return [Check] запрос не поступил
        def missing(role, route)
          check(role, address_title(route), false, "запрос до провайдера не дошёл")
        end

        # @param role [Symbol]
        # @param route [StubServer::Route]
        # @param received [StubServer::Received]
        # @return [Check] соответствие глагола и адреса плану
        def address(role, route, received)
          ok = route.http_method == received.http_method && route.pattern.match?(received.path)
          check(role, address_title(route), ok, "пришло #{received.http_method} #{received.path}")
        end

        # @param route [StubServer::Route]
        # @return [String]
        def address_title(route) = "запрос уходит на #{route.http_method} #{route.path}"

        # Ключ ищется там, где его объявил провайдер.
        # @param role [Symbol]
        # @param received [StubServer::Received]
        # @return [Check, nil] nil, если схема авторизации не определена
        def signature(role, received)
          scheme = @credentials.primary
          return nil if scheme.nil? || scheme.kind == :unsupported

          check(role, "запрос подписан: #{scheme.name}", signed?(scheme, received),
                "ключа нет ни в заголовках, ни в адресе")
        end

        # @param scheme [Analysis::CredentialsPlanner::Scheme]
        # @param received [StubServer::Received]
        # @return [Boolean]
        def signed?(scheme, received)
          case scheme.kind
          when :api_key then key?(scheme, received)
          when :bearer then received.headers["authorization"].to_s.start_with?("Bearer ")
          when :basic then received.headers["authorization"].to_s.start_with?("Basic ")
          else false
          end
        end

        # @param scheme [Analysis::CredentialsPlanner::Scheme]
        # @param received [StubServer::Received]
        # @return [Boolean] ключ передан в объявленном провайдером месте
        def key?(scheme, received)
          name = scheme.parameter.to_s
          return received.query.include?("#{name}=") if scheme.location == "query"

          !received.headers[name.downcase].to_s.empty?
        end

        # Тело сверяется с планом запроса.
        # @param role [Symbol]
        # @param received [StubServer::Received]
        # @return [Check, nil] nil, если тело запроса не планировалось
        def body(role, received)
          fields = @blueprint.calls[role]&.payload.to_a.map(&:name)
          return nil if fields.empty?

          missing = fields - parsed(received.body).keys
          check(role, "в теле запроса поля провайдера: #{fields.join(", ")}", missing.empty?,
                "не хватает полей: #{missing.join(", ")}")
        end

        # @param raw [String] тело запроса без обработки
        # @return [Hash] разобранное тело; при ошибке разбора — пустой хеш
        def parsed(raw)
          value = JSON.parse(raw.to_s)
          value.is_a?(Hash) ? value : {}
        rescue JSON::ParserError
          {}
        end

        # @param role [Symbol]
        # @param title [String] содержание проверки
        # @param passed [Boolean] результат
        # @param detail [String] описание расхождения
        # @return [Check]
        def check(role, title, passed, detail)
          Check.new(role: role, title: title, ok: passed, detail: passed ? nil : detail)
        end
      end
    end
  end
end
