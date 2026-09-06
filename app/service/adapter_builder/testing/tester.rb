# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Testing
      # Последняя ступень: собранный класс вызывается на своих фикстурах у подставного
      # провайдера. На сборку итог не влияет, он уходит в отчёт.
      class Tester
        include Ports::Tester

        NO_PROBE = "профиль контракта не содержит probe.rb — вызвать собранный класс нечем"
        # Окружение процесса одно на всех, поэтому прогоны не идут параллельно.
        LOCK = Mutex.new

        # @param rules [Ports::Rules] роли контракта, словарь ошибок и проба контракта
        def initialize(rules)
          @rules = rules
        end

        # @param source [String] исходник собранного класса
        # @param blueprint [Models::Blueprint] всё, что инструмент решил
        # @return [Report] состав проверок и их результаты
        def call(source:, blueprint:)
          return Report.new(notes: [NO_PROBE]) if probe_source.nil?

          LOCK.synchronize { run(source, blueprint) }
        rescue StandardError => e
          Report.new(notes: ["проверка не выполнена: #{e.class}: #{e.message}"])
        end

        private

        # @return [String, nil] исходник пробы контракта
        def probe_source = @rules.contract.probe

        # @param source [String]
        # @param blueprint [Models::Blueprint]
        # @return [Report]
        def run(source, blueprint)
          server = StubServer.new(blueprint).start
          with_env(environment(blueprint, server.url)) do
            report(server, blueprint, sandbox(source, blueprint))
          end
        rescue Sandbox::LoadFailure => e
          Report.new(checks: [load_check(blueprint, false, e.message)])
        ensure
          server&.stop
        end

        # @param source [String]
        # @param blueprint [Models::Blueprint]
        # @return [Object] проба, связанная с собранным классом
        # @raise [Sandbox::LoadFailure] исходник не загрузился
        def sandbox(source, blueprint)
          Sandbox.new(probe: probe_source, source: source,
                      class_name: blueprint.class_name).call
        end

        # @param server [StubServer]
        # @param blueprint [Models::Blueprint]
        # @param probe [Object] проба контракта, связанная с собранным классом
        # @return [Report]
        def report(server, blueprint, probe)
          scenario = Scenario.new(rules: @rules, blueprint: blueprint, server: server,
                                  probe: probe, payment: Payment.new(blueprint))
          Report.new(checks: [load_check(blueprint, true)] + scenario.call)
        end

        # Загрузка учитывается как отдельная проверка: без неё остальные не выполняются.
        # @param blueprint [Models::Blueprint]
        # @param passed [Boolean]
        # @param detail [String, nil]
        # @return [Report::Check]
        def load_check(blueprint, passed, detail = nil)
          Report::Check.new(role: blueprint.class_name, ok: passed, detail: detail,
                            title: "собранный класс загружается и создаётся")
        end

        # Адрес и ключи класс читает из окружения; значения ключей произвольны.
        # @param blueprint [Models::Blueprint]
        # @param url [String] адрес подставного провайдера
        # @return [Hash{String => String}]
        def environment(blueprint, url)
          prefix = blueprint.env_prefix
          keys = Array(blueprint.credentials.primary&.credentials)
          keys.to_h { |name| ["#{prefix}_#{name.to_s.upcase}", "rsocket-check-#{name}"] }
              .merge("#{prefix}_BASE_URL" => url)
        end

        # @param values [Hash{String => String}] значения для записи в окружение
        # @return [Object] результат блока
        def with_env(values)
          previous = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
          values.each { |key, value| ENV[key] = value }
          yield
        ensure
          previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
        end
      end
    end
  end
end
