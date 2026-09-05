# frozen_string_literal: true

require "erb"
require "json"
require "pathname"

module Service
  module AdapterBuilder
    module Rendering
      # Печать класса по шаблону профиля контракта. Шаблон ничего не вычисляет: всё,
      # что требует решений, посчитано раньше и разложено по Blueprint, а здесь только
      # форматирование — иначе правила размазываются между конфигом и вёрсткой.
      #
      # Шаблон приходит снаружи: под какой интерфейс собирается класс, решает профиль,
      # а рендерер одинаково печатает любой из них.
      class Renderer
        include Ports::Renderer

        # @param outputs [Array<Config::Settings::Output>] что печатает профиль контракта
        def initialize(outputs)
          @outputs = outputs
        end

        # Профиль объявляет несколько выходных файлов — сервис, инструкцию,
        # фикстуры, — и все они печатаются из одного и того же Blueprint.
        # @param blueprint [Models::Blueprint]
        # @return [Hash{String => String}] имя файла → его содержимое
        def call(blueprint)
          context = Context.new(blueprint)
          @outputs.to_h do |output|
            [output.name_for(blueprint.provider), render(output.template, context)]
          end
        end

        private

        # @param template [String] сам шаблон
        # @param context [Context] в нём шаблон исполняется
        # @return [String]
        def render(template, context)
          ERB.new(template, trim_mode: "-").result(context.binding_for_template)
        end

        # Печать литералов Ruby: тела запросов, хеши и пути до значений в ответе.
        # Вынесено из контекста, потому что это работа с текстом, а не с решениями.
        module Literal
          LABEL = /\A[A-Za-z_][A-Za-z0-9_]*\z/

          # Тело запроса как литерал: имена свойств оставляем ровно такими, как их
          # назвал провайдер, — тело уходит в JSON без переименований.
          # @param fields [Array<PayloadBuilder::Field>]
          # @param indent [Integer] отступ уровня в пробелах
          # @return [String] пары ключ-значение через запятую, без хвостовой
          def payload_literal(fields, indent)
            pad = " " * indent
            fields.map { |field| "#{pad}#{field_literal(field, indent)}" }.join(",\n")
          end

          # Путь до значения в теле ответа или webhook — имена полей как у провайдера.
          # @param path [Array<String>]
          # @return [String] аргументы для чтения тела
          def path_literal(path)
            Array(path).map { |part| "\"#{part}\"" }.join(", ")
          end

          # @param entries [Hash{String => String}] имя ключа → выражение на Ruby
          # @return [String] пары хеша без фигурных скобок
          def literal_hash(entries)
            entries.map { |key, value| "\"#{key}\" => #{value}" }.join(", ")
          end

          private

          # @param field [PayloadBuilder::Field]
          # @param indent [Integer]
          # @return [String] поле с незаполненным источником печатается с TODO
          def field_literal(field, indent)
            key = field.name.match?(LABEL) ? "#{field.name}:" : "\"#{field.name}\":"
            return nested_literal(key, field, indent) unless field.leaf?
            return "#{key} #{field.source}" unless field.source.nil?

            "#{key} nil # TODO: правила не знают, чем заполнить это поле"
          end

          # @param key [String] ключ с двоеточием
          # @param field [PayloadBuilder::Field] поле с вложенными
          # @param indent [Integer]
          # @return [String]
          def nested_literal(key, field, indent)
            "#{key} {\n#{payload_literal(field.children, indent + 2)}\n#{" " * indent}}"
          end
        end

        # Печать вызова транспорта: во что превращается запланированный запрос.
        module Requests
          # Запрос роли целиком: глагол, адрес с подставленными параметрами и всё,
          # что у запроса есть кроме них.
          # @param role [Symbol] имя роли контракта
          # @param body_method [String] имя приватного метода, собирающего тело
          # @return [String] вызов транспорта
          def request_for(role, body_method)
            request_expression(call_for(role), body_method)
          end

          # @param call [Analysis::CallPlanner::Request]
          # @param body_method [String]
          # @return [String]
          def request_expression(call, body_method)
            "request(#{request_arguments(call, body_method).join(", ")})#{todo_comment(call)}"
          end

          private

          # @param call [Analysis::CallPlanner::Request]
          # @param body_method [String]
          # @return [Array<String>] аргументы вызова в порядке объявления
          def request_arguments(call, body_method)
            arguments = [":#{call.http_method}", path_expression(call)]
            arguments << "body: #{body_method}" if call.payload.any?
            arguments << "query: { #{literal_hash(call.query)} }" if call.query.any?
            arguments << "headers: { #{literal_hash(call.headers)} }" if call.headers.any?
            arguments
          end

          # Адрес с подставленными параметрами пути: шаблон провайдера превращается
          # в строку с интерполяцией, а не в format — так его читать проще.
          # @param call [Analysis::CallPlanner::Request]
          # @return [String] литерал строки на Ruby
          def path_expression(call)
            filled = call.path.gsub(/\{([^}]+)\}/) do
              "\#{#{call.path_arguments.fetch(Regexp.last_match(1), "nil")}}"
            end
            "\"#{filled}\""
          end

          # @param call [Analysis::CallPlanner::Request]
          # @return [String] хвостовой комментарий, если параметр заполнить нечем
          def todo_comment(call)
            return "" if call.unfilled.empty?

            " # TODO: правила не знают, чем заполнить #{call.unfilled.join(", ")}"
          end
        end

        # Форматирование значений Blueprint в текст Ruby.
        class Context
          include Literal
          include Requests

          # @param blueprint [Models::Blueprint]
          def initialize(blueprint)
            @blueprint = blueprint
          end

          # @return [Binding] контекст, в котором исполняется шаблон
          def binding_for_template = binding

          # Поля Blueprint читаются в шаблоне по имени: перечислять два десятка делегатов
          # ради этого незачем.
          # @param name [Symbol]
          # @return [Object]
          def method_missing(name, *, &)
            @blueprint.respond_to?(name) ? @blueprint.public_send(name, *, &) : super
          end

          # @param name [Symbol]
          # @param include_private [Boolean]
          # @return [Boolean]
          def respond_to_missing?(name, include_private = false)
            @blueprint.respond_to?(name) || super
          end

          # @param role [Symbol]
          # @return [Boolean] печатать запрос или заглушку
          def bound?(role) = @blueprint.bindings[role]&.bound? || false

          # @param role [Symbol]
          # @return [Analysis::CallPlanner::Request, nil] запланированный запрос роли
          def call_for(role) = @blueprint.calls[role]

          # @param role [Symbol]
          # @return [Boolean] есть ли у запроса роли тело
          def body?(role) = call_for(role)&.payload&.any? || false

          # @param role [Symbol]
          # @return [Models::RoleBinding, nil]
          def binding_for(role) = @blueprint.bindings[role]

          # Комментарий над методом: откуда роль взялась и по каким правилам.
          # @param role [Symbol]
          # @return [Array<String>] строки комментария
          def origin(role)
            binding = binding_for(role)
            return ["роль не распознана: #{binding&.explanation}"] unless binding&.bound?

            [endpoint_line(binding), rules_line(binding)]
          end

          # @param binding [Models::RoleBinding]
          # @return [String] какой эндпоинт провайдера закрывает роль
          def endpoint_line(binding)
            operation = binding.operation
            "#{binding.role.title.capitalize}: #{binding.endpoint} (#{operation.method_name})"
          end

          # @param binding [Models::RoleBinding]
          # @return [String] счёт, порог и поля, по которым роль назначена
          def rules_line(binding)
            fields = binding.matched_rules.map(&:field).uniq.join(", ")
            score = "счёт #{binding.score} при пороге #{binding.role.threshold}"
            "роль назначена правилами: #{score} по полям #{fields}. Разбор — в mapping.yml"
          end

          # @return [Array<Array(String, String)>] пары для карты статусов, ключи в нижнем регистре
          def status_entries
            status_map.map { |token, contract| [token.to_s.downcase, contract] }.uniq.sort
          end

          # Запись ошибки отдаётся целиком: из чего она состоит, решает контракт —
          # одному нужен символ HTTP-статуса, другому хватает кода.
          # @return [Array<Array(Integer, Hash)>] код ответа и запись контракта
          def error_entries
            error_map.to_a
          end

          # @return [Array<Array(String, String)>] код ошибки → что с ней делать
          def action_entries
            error_map.values.map { |entry| [entry.fetch(:code), entry.fetch(:action)] }.uniq.sort
          end

          # @param prefix [String] начало названия действия, например "retry"
          # @return [Array<String>] коды ошибок, с которыми контракт делает это действие
          def error_codes_for(prefix)
            matched = error_map.values.select { |entry| entry.fetch(:action).start_with?(prefix) }
            matched.map { |entry| entry.fetch(:code) }.uniq.sort
          end

          # Границы суммы и список валют — константами, чтобы их было видно сразу.
          # Имя константы назначил контракт, значение и источник нашёл разбор.
          # @return [Array<Array(String, Object, String)>] имя константы, значение и источник
          def constraint_constants
            constraints.map do |constraint|
              [constraint.constant, constant_value(constraint), constraint.source]
            end
          end

          # Условия предпроверки в том же порядке, что и константы над ними.
          # @return [Array<Array(String, String)>] условие и код отказа
          def constraint_checks
            constraints.map { |constraint| [check_condition(constraint), constraint.code] }
          end

          # @return [Hash{String => Object}] документ фикстур целиком
          def fixtures_document
            Fixtures.new(@blueprint).to_h
          end

          # @param value [Object] что печатаем
          # @return [String] JSON с отступами — файл читает человек
          def json(value)
            JSON.pretty_generate(value)
          end

          # Переменные окружения, которые нужно задать перед первым запросом:
          # адрес провайдера и ключи выбранной схемы авторизации.
          # @return [Array<String>]
          def env_variables
            keys = Array(credentials.primary&.credentials)
            ["#{env_prefix}_BASE_URL"] + keys.map { |key| "#{env_prefix}_#{key.upcase}" }
          end

          # @return [String, nil] эндпоинт, на который провайдер шлёт уведомления
          def callback_endpoint
            item = @blueprint.bindings.values.find do |binding|
              binding.bound? && binding.role.trait?(:receives_callback)
            end
            item&.endpoint
          end

          # Способ выплаты из примера запроса — по нему заполняют каталог методов.
          # @return [String, nil]
          def recipient_type
            sample = fixtures.calls.values.first&.request
            return nil unless sample.is_a?(Hash)

            nested = sample.values.find { |value| value.is_a?(Hash) && value["type"] }
            nested && nested["type"]
          end

          # @return [Boolean] есть ли чем проверять подпись webhook
          def signature?
            callback.supported && !callback.signature_header.nil? &&
              !callback.signature_algorithm.nil?
          end

          private

          # @param constraint [Models::Constraint]
          # @return [String, Numeric] литерал значения константы
          def constant_value(constraint)
            return constraint.value unless constraint.currency?

            "%w[#{Array(constraint.value).join(" ")}].freeze"
          end

          # @param constraint [Models::Constraint]
          # @return [String] условие отказа
          def check_condition(constraint)
            name = constraint.constant
            subject = constraint.subject
            return "unless #{name}.include?(#{subject}.to_s)" if constraint.currency?

            "if #{subject} #{constraint.operator} #{name}"
          end
        end
      end
    end
  end
end
