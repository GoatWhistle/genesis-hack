# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Разобранное описание и розданные роли → Blueprint для шаблона. Здесь никаких
      # решений о ролях: они уже приняты, а этот класс только достаёт из описания
      # всё, что понадобится напечатать.
      #
      # Имён ролей этот класс не знает: у каждого контракта они свои. Нужную роль он
      # находит по признаку из конфига — кто создаёт операцию, кто принимает webhook,
      # чьи ответы описывают состояния.
      class BlueprintFactory
        # Разбор по частям: webhook, статусы, ограничения, вызовы, авторизация,
        # тестовые материалы.
        Analysis = Struct.new(:bindings, :callback, :statuses, :limits, :calls, :credentials,
                              :fixtures, keyword_init: true)

        # @param rules [Ports::Rules] роли контракта, словари, статусы и ограничения
        def initialize(rules)
          @rules = rules
        end

        # @param spec [Models::ApiSpec] разобранное описание API
        # @param names [Builder::Naming] имена, производные от названия провайдера
        # @param bindings [Hash{Symbol => Models::RoleBinding}] розданные роли
        # @return [Models::Blueprint]
        def call(spec:, names:, bindings:)
          analysis = analyse(spec, bindings)
          sections = status_section(analysis).merge(money_section(analysis), call_section(analysis))
          Models::Blueprint.new(**names.to_h, **sections, **rest(spec, analysis))
        end

        private

        # @param spec [Models::ApiSpec]
        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [Analysis] итоги всех разборщиков
        def analyse(spec, bindings)
          callback = CallbackAnalyzer.new(@rules).call(callback_operation(bindings))
          statuses = statuses_for(bindings)
          Analysis.new(bindings: bindings, callback: callback, statuses: statuses,
                       **parts(spec, bindings, callback, statuses))
        end

        # Разборщики, которым нужны итоги разбора webhook и состояний.
        # @param spec [Models::ApiSpec]
        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @param callback [CallbackAnalyzer::Result]
        # @param statuses [StatusMapper::Result]
        # @return [Hash] остальные части разбора
        def parts(spec, bindings, callback, statuses)
          create = operation_with(bindings, :creates_operation)
          {
            calls: CallPlanner.new(@rules).call(bindings),
            limits: ConstraintMiner.new(@rules).call(operation: create, spec_text: spec.text),
            credentials: CredentialsPlanner.new(@rules).call(spec, create),
            fixtures: FixturePlanner.new(@rules).call(bindings: bindings, statuses: statuses,
                                                      callback: callback)
          }
        end

        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [StatusMapper::Result]
        def statuses_for(bindings)
          StatusMapper.new(@rules).call(
            operations: status_operations(bindings),
            callback_schema: callback_operation(bindings)&.request_schema
          )
        end

        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [Models::ApiOperation, nil] операция, описывающая webhook
        def callback_operation(bindings) = operation_with(bindings, :receives_callback)

        # @param spec [Models::ApiSpec]
        # @param analysis [Analysis]
        # @return [Hash] то, что переносится в Blueprint без обработки
        def rest(spec, analysis)
          {
            base_url: spec.base_url, http: @rules.http, bindings: analysis.bindings,
            callback: analysis.callback, credentials: analysis.credentials,
            fixtures: analysis.fixtures, warnings: warnings(analysis)
          }
        end

        # @param analysis [Analysis]
        # @return [Hash] карты статусов и событий и пути до значений в ответе
        def status_section(analysis)
          {
            status_map: analysis.statuses.status_map, event_map: analysis.statuses.event_map,
            status_field: analysis.statuses.status_path,
            error_map: ErrorMapper.new(@rules).call(status_operations(analysis.bindings)),
            created_id_field: created_id_field(analysis.bindings)
          }
        end

        # @param analysis [Analysis]
        # @return [Hash] предпроверки, единицы суммы и выражение её печати
        def money_section(analysis)
          {
            constraints: analysis.limits.constraints, amount_multiplier: analysis.limits.multiplier,
            amount_expression: analysis.limits.amount_expression
          }
        end

        # @param analysis [Analysis]
        # @return [Hash] запросы по ролям, ходящим к провайдеру
        def call_section(analysis)
          { calls: analysis.calls.requests }
        end

        # Где в ответе на создание лежит идентификатор операции провайдера. Не нашли —
        # берём id: так обёртка хотя бы соберётся, а догадка попадёт в отчёт.
        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [Array<String>] путь до поля
        def created_id_field(bindings)
          schema = operation_with(bindings, :creates_operation)&.success_response&.dig(:schema)
          patterns = @rules.callback_fields.fetch(:operation_id)
          Parsing::SchemaProbe.new(schema).find(patterns)&.path || ["id"]
        end

        # Чьи ответы описывают состояния операции. Порядок задан контрактом: у
        # статус-запроса перечисление полнее всего, остальные идут подстраховкой.
        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [Array<Models::ApiOperation>] операции этих ролей, которым нашёлся метод
        def status_operations(bindings)
          @rules.status_sources.filter_map { |name| bindings[name]&.operation }
        end

        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @param trait [Symbol] признак роли из Config::Settings::Role::TRAITS
        # @return [Models::ApiOperation, nil] nil, если роли нет или она осталась заглушкой
        def operation_with(bindings, trait)
          role = @rules.role_with(trait)
          role && bindings[role.name]&.operation
        end

        # Всё, в чём инструмент не уверен, собирается в одном месте: и в сводку CLI,
        # и в отчёт уходит один и тот же список.
        # @param analysis [Analysis]
        # @return [Array<String>]
        def warnings(analysis)
          stub_warnings(analysis.bindings) + status_warnings(analysis.statuses) +
            analysis.calls.warnings + analysis.limits.notes +
            analysis.callback.notes + analysis.credentials.notes
        end

        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @return [Array<String>] по строке на каждую нераспознанную роль
        def stub_warnings(bindings)
          stubs = bindings.values.reject(&:bound?)
          stubs.map { |binding| "#{binding.role.title}: #{binding.explanation}" }
        end

        # @param statuses [StatusMapper::Result]
        # @return [Array<String>] состояния провайдера, которым не нашлось статуса контракта
        def status_warnings(statuses)
          statuses.unmapped.map { |token| "состояние «#{token}» не перевести в статус контракта" }
        end
      end
    end
  end
end
