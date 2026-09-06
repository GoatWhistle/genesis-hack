# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Testing
      # На каждую роль прогон с успехом и по прогону на каждый описанный отказ.
      class Scenario
        Check = Report::Check

        # @param rules [Ports::Rules] роли контракта и словарь ошибок
        # @param blueprint [Models::Blueprint] всё, что инструмент решил
        # @param server [StubServer] запущенный подставной провайдер
        # @param probe [Object] проба контракта поверх собранного класса
        # @param payment [Payment] заявка для вызова
        def initialize(rules:, blueprint:, server:, probe:, payment:)
          @rules = rules
          @blueprint = blueprint
          @server = server
          @probe = probe
          @payment = payment
          @wire = Wire.new(blueprint)
        end

        # @return [Array<Check>] проверки в порядке выполнения
        def call
          @blueprint.calls.keys.flat_map { |role| success(role) + errors(role) } + callbacks
        end

        private

        # @param role [Symbol]
        # @return [Array<Check>] проверки отправленного запроса и возвращённого значения
        def success(role)
          outcome = invoke(role, @server.success_code(role))
          @wire.call(role: role, route: @server.route_for(role), received: @server.last) +
            [accepted(role, outcome), value(role, outcome)].compact
        end

        # @param role [Symbol]
        # @return [Array<Check>] по проверке на каждый описанный отказ провайдера
        def errors(role)
          @server.error_codes(role).map { |code| error(role, code) }
        end

        # @param role [Symbol]
        # @param code [Integer] код ответа подставного провайдера
        # @return [Hash] { ok:, code:, value: } от пробы контракта
        def invoke(role, code)
          @server.answer(role, code)
          ask { @probe.call(role, @payment.to_h) }
        end

        # @param role [Symbol]
        # @param outcome [Hash]
        # @return [Check] распознан ли успешный ответ как успех
        def accepted(role, outcome)
          check(role, "успешный ответ разобран как успех", outcome[:ok] == true,
                "класс вернул отказ: #{(outcome[:code] || outcome[:error]).inspect}")
        end

        # @param role [Symbol]
        # @param outcome [Hash]
        # @return [Check, nil] проверка возвращённого значения: идентификатора или состояния
        def value(role, outcome)
          return identifier(role, outcome) if creates?(role)

          status(role, outcome)
        end

        # @param role [Symbol]
        # @param outcome [Hash]
        # @return [Check] прочитан ли идентификатор операции из ответа
        def identifier(role, outcome)
          expected = @payment.provider_id
          check(role, "идентификатор операции прочитан из ответа",
                outcome[:value].to_s == expected,
                "в ответе #{expected}, а класс отдал #{outcome[:value].inspect}")
        end

        # @param role [Symbol]
        # @param outcome [Hash]
        # @return [Check, nil] nil, если в примере ответа состояние отсутствует
        def status(role, outcome)
          expected = expected_status(role)
          return nil if expected.nil?

          check(role, "состояние из ответа переведено в статус контракта: #{expected}",
                outcome[:value].to_s == expected, "класс отдал #{outcome[:value].inspect}")
        end

        # @param role [Symbol]
        # @return [String, nil] ожидаемый статус контракта для этой роли
        def expected_status(role)
          path = @blueprint.status_fields.to_h.fetch(role, @blueprint.status_field)
          token = dig(@payment.success_response(role), Array(path))
          return nil if token.nil?

          @blueprint.status_map.find { |name, _| name.to_s.casecmp?(token.to_s) }&.last
        end

        # @param role [Symbol]
        # @param code [Integer] код отказа провайдера
        # @return [Check] сопоставлен ли код ошибке контракта
        def error(role, code)
          expected = expected_error(code)
          outcome = invoke(role, code)
          ok = outcome[:ok] == false && same_code?(outcome[:code], expected)
          check(role, "ответ #{code} разобран как отказ #{expected}", ok,
                "класс вернул #{outcome[:ok] ? "успех" : outcome[:code].inspect}")
        end

        # @param code [Integer]
        # @return [String] код ошибки контракта для этого ответа
        def expected_error(code)
          @blueprint.error_map.fetch(code) { @rules.error_for(code) }.fetch(:code).to_s
        end

        # Код сравнивается без приставки: контракты печатают его по-разному.
        # @param actual [String, Symbol, nil] значение, возвращённое классом
        # @param expected [String] код контракта
        # @return [Boolean]
        def same_code?(actual, expected)
          actual.to_s.split(".").last == expected
        end

        # @return [Array<Check>] по проверке на каждое описанное уведомление
        def callbacks
          role = @rules.role_with(:receives_callback)&.name
          return [] unless role && @blueprint.bindings[role]&.bound?

          @blueprint.fixtures.callbacks.map { |item| callback(role, item) }
        end

        # @param role [Symbol]
        # @param item [Analysis::FixturePlanner::Callback]
        # @return [Check] соответствие статуса, в который переведено уведомление
        def callback(role, item)
          outcome = ask { @probe.callback(role, item.payload) }
          check(role, "уведомление #{item.name} переводится в #{item.expected}",
                outcome[:status].to_s == item.expected.to_s,
                "класс отдал #{outcome[:status].inspect} #{outcome[:error]}".strip)
        end

        # Падение пробы — тоже итог проверки, а не повод оборвать остальные.
        # @return [Hash] результат пробы либо описание исключения
        def ask
          yield
        rescue StandardError => e
          { ok: false, error: "#{e.class}: #{e.message}" }
        end

        # @param role [Symbol]
        # @return [Boolean] создаёт ли эта роль операцию у провайдера
        def creates?(role)
          @blueprint.bindings[role]&.role&.trait?(:creates_operation) || false
        end

        # @param body [Hash, nil]
        # @param path [Array<String>]
        # @return [Object, nil]
        def dig(body, path)
          Parsing::DataPath.read(body, path)
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
