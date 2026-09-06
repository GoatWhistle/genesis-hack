# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Примеры запросов, ответов и уведомлений с ожидаемым статусом контракта.
      class FixturePlanner
        # Один эндпоинт: запрос к нему и его ответы.
        Case = Struct.new(:role, :title, :endpoint, :request, :responses, keyword_init: true)
        # Уведомление и статус контракта, в который оно переводится.
        Callback = Struct.new(:name, :payload, :expected, keyword_init: true)
        Result = Struct.new(:calls, :callbacks, keyword_init: true)

        # @param rules [Ports::Rules] роли контракта
        def initialize(rules)
          @rules = rules
          @sample = SampleBuilder.new
        end

        # @param bindings [Hash{Symbol => Models::RoleBinding}] розданные роли
        # @param statuses [StatusMapper::Result] карты состояний и путь до статуса
        # @param callback [CallbackAnalyzer::Result] разбор уведомления
        # @return [Result]
        def call(bindings:, statuses:, callback:)
          @statuses = statuses
          @callback = callback
          Result.new(calls: calls(bindings), callbacks: callbacks(bindings))
        end

        private

        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [Hash{Symbol => Case}] по роли, ходящей к провайдеру и получившей операцию
        def calls(bindings)
          @rules.roles_with(:calls_provider).to_h do |role|
            [role.name, build_case(role, bindings[role.name])]
          end.compact
        end

        # @param role [Config::Settings::Role]
        # @param binding [Models::RoleBinding, nil]
        # @return [Case, nil]
        def build_case(role, binding)
          return nil unless binding&.bound?

          operation = binding.operation
          Case.new(role: role.name, title: role.title, endpoint: binding.endpoint,
                   request: example(operation.request_example, operation.request_schema),
                   responses: responses(operation))
        end

        # Все описанные ответы, включая ошибочные: по ним проверяется разбор 4xx и 5xx.
        # @param operation [Models::ApiOperation]
        # @return [Hash{String => Hash}] код ответа → пример тела
        def responses(operation)
          operation.responses.to_h do |code, body|
            [code.to_s, example(body[:example], body[:schema])]
          end.compact
        end

        # Пример из описания приоритетнее синтезированного.
        # @param described [Object, nil] пример из описания
        # @param schema [Hash, nil] схема на случай, если примера нет
        # @return [Hash, nil]
        def example(described, schema)
          return as_data(described) if described.is_a?(Hash)

          @sample.call(schema)
        end

        # Ключи приводятся к тому виду, в каком их передаёт провайдер.
        # @param value [Object]
        # @return [Object] то же значение со строковыми ключами
        def as_data(value)
          case value
          when Hash then value.to_h { |key, item| [key.to_s, as_data(item)] }
          when Array then value.map { |item| as_data(item) }
          else value
          end
        end

        # По уведомлению на событие; без перечисления событий — на состояние.
        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [Array<Callback>]
        def callbacks(bindings)
          operation = callback_operation(bindings)
          return [] if operation.nil?

          base = callback_body(operation)
          return [] if base.nil?
          return build_callbacks(base, @statuses.event_map, :event) if events_known?

          build_callbacks(base, @statuses.status_map, :status)
        end

        # Синтезированное тело даёт форму, пример из описания — настоящие значения.
        # @param operation [Models::ApiOperation]
        # @return [Hash, nil] тело уведомления до подстановки события
        def callback_body(operation)
          synthesized = @sample.call(operation.request_schema)
          described = operation.request_example
          return synthesized unless described.is_a?(Hash)

          (synthesized || {}).merge(as_data(described))
        end

        # @return [Boolean] описал ли провайдер перечисление событий уведомления
        def events_known? = !@statuses.event_map.empty?

        # @param base [Hash] тело уведомления, общее для всех случаев
        # @param source [Hash{String => String}] событие или состояние → статус контракта
        # @param kind [Symbol] :event или :status — по какому полю названо уведомление
        # @return [Array<Callback>]
        def build_callbacks(base, source, kind)
          source.map do |name, contract_status|
            payload = base.dup
            overrides(kind, name, contract_status).each do |path, value|
              assign(payload, path, value)
            end
            Callback.new(name: name, payload: payload, expected: contract_status)
          end
        end

        # @param payload [Hash]
        # @param path [Array<String>] путь до поля
        # @param value [Object]
        # @return [void]
        def assign(payload, path, value)
          *head, last = path
          target = head.reduce(payload) { |node, key| node.is_a?(Hash) ? node[key] : nil }
          target[last] = value if target.is_a?(Hash) && target.key?(last)
        end

        # Поле статуса заполняется состоянием того же статуса контракта.
        # @param kind [Symbol] :event или :status
        # @param name [String] имя события или состояния
        # @param contract_status [String] статус контракта
        # @return [Hash{Array<String> => String}] путь до поля → значение
        def overrides(kind, name, contract_status)
          token = kind == :status ? name : @statuses.status_map.key(contract_status)
          paths = {}
          paths[@callback.event_path] = name if kind == :event && @callback.event_path
          paths[@callback.status_path] = token if @callback.status_path && token
          paths
        end

        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [Models::ApiOperation, nil] операция, описывающая уведомление
        def callback_operation(bindings)
          role = @rules.role_with(:receives_callback)
          role && bindings[role.name]&.operation
        end
      end
    end
  end
end
