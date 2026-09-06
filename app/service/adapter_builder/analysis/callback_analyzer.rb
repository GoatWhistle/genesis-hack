# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Разбор webhook: где в теле идентификатор, событие, статус, код ошибки и чем подписан запрос.
      class CallbackAnalyzer
        Result = Struct.new(:supported, :operation_path, :event_path, :status_path, :error_path,
                            :signature_header, :signature_algorithm, :notes, keyword_init: true)

        # @param rules [Ports::Rules] словарь полей webhook и заголовков
        def initialize(rules)
          @rules = rules
        end

        # @param operation [Models::ApiOperation, nil] операция роли process_callback
        # @return [Result] supported: false, если webhook не описан
        def call(operation)
          return unsupported if operation.nil?

          header = signature_header(operation)
          Result.new(supported: true, notes: notes(header),
                     **body_fields(operation), **signature(operation, header))
        end

        # Расположение идентификатора, события, статуса и кода ошибки в теле webhook.
        # @param operation [Models::ApiOperation]
        # @return [Hash{Symbol => Array<String>, nil}] пути к полям
        def body_fields(operation)
          probe = Parsing::SchemaProbe.new(operation.request_schema)
          fields = @rules.callback_fields
          {
            operation_path: path(probe, fields.fetch(:operation_id)),
            event_path: path(probe, fields.fetch(:event)),
            status_path: path(probe, fields.fetch(:status)),
            error_path: error_path(probe, fields)
          }
        end

        private

        # @param operation [Models::ApiOperation]
        # @param header [Hash, nil] параметр-заголовок, содержащий подпись
        # @return [Hash{Symbol => String, nil}]
        def signature(operation, header)
          { signature_header: header&.fetch(:name),
            signature_algorithm: signature_algorithm(operation, header) }
        end

        # @return [Result] результат для провайдера без описанного webhook
        def unsupported
          Result.new(supported: false,
                     notes: ["провайдер не описывает webhook — статус узнаётся опросом"])
        end

        # @param probe [Parsing::SchemaProbe]
        # @param patterns [Array<Regexp>]
        # @return [Array<String>, nil] путь к полю
        def path(probe, patterns)
          probe.find(patterns)&.path
        end

        # Код ошибки обычно завёрнут в объект: error → { code, message }.
        # @param probe [Parsing::SchemaProbe]
        # @param fields [Hash{Symbol => Array<Regexp>}] словарь полей webhook
        # @return [Array<String>, nil] путь до кода ошибки, а не до объекта вокруг него
        def error_path(probe, fields)
          found = probe.find(fields.fetch(:error_code))
          return nil if found.nil?
          return found.path unless found.node[:type].to_s == "object"

          detail = Parsing::SchemaProbe.new(found.node).find(fields.fetch(:error_detail))
          detail ? found.path + [detail.path.last] : found.path
        end

        # @param operation [Models::ApiOperation]
        # @return [Hash, nil] параметр-заголовок, распознанный правилами как подпись
        def signature_header(operation)
          operation.header_parameters.find do |parameter|
            @rules.header_kind(parameter[:name]) == :signature
          end
        end

        # Алгоритм ищется в тексте: отдельного поля под него в OpenAPI нет.
        # @param operation [Models::ApiOperation]
        # @param header [Hash, nil]
        # @return [String, nil] например sha256
        def signature_algorithm(operation, header)
          return nil if header.nil?

          text = [operation.text, header[:description]].compact.join("\n")
          @rules.headers.fetch(:signature_algorithms).each do |pattern|
            match = pattern.match(text)
            return "sha#{match[:bits]}" if match
          end
          nil
        end

        # @param header [Hash, nil]
        # @return [Array<String>] сообщения о подписи для отчёта
        def notes(header)
          return ["подпись в описании webhook не найдена — проверять нечего"] if header.nil?

          ["подпись приходит в заголовке #{header[:name]}"]
        end
      end
    end
  end
end
