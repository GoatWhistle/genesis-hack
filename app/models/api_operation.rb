# frozen_string_literal: true

module Models
  # Операция описания API: $ref раскрыты, ответы разложены по кодам.
  class ApiOperation
    attr_reader :operation_id, :http_method, :path, :summary, :description, :tags,
                :parameters, :responses, :security

    # @param operation_id [String, nil] operationId из описания
    # @param http_method [String, Symbol] глагол HTTP, приводится к нижнему регистру
    # @param path [String] шаблон пути, например /payouts/{id}
    # @param summary [String, nil] однострочное описание операции
    # @param description [String, nil] развёрнутое описание операции
    # @param tags [Array<String>] теги операции
    # @param parameters [Array<Hash>] записи { name:, in:, required:, description:, schema: }
    # @param request [Hash] тело запроса: { schema:, example: }, $ref уже раскрыты
    # @param responses [Hash{String => Hash}] код ответа → { description:, schema: }
    # @param security [Array<Hash>, nil] требования авторизации операции
    def initialize(operation_id:, http_method:, path:, summary: nil, description: nil, tags: [],
                   parameters: [], request: {}, responses: {}, security: nil)
      @operation_id = operation_id
      @http_method = http_method.to_s.downcase
      @path = path
      @summary = summary
      @description = description
      @tags = tags
      @parameters = parameters
      @request = request
      @responses = responses
      @security = security
    end

    # @return [Hash, nil] схема тела запроса
    def request_schema = @request[:schema]

    # Пример тела из описания провайдера; используется при построении фикстур.
    # @return [Hash, nil]
    def request_example = @request[:example]

    # Имя операции: operationId в snake_case, иначе из глагола HTTP и пути.
    # @return [String]
    def method_name
      return snake_case(operation_id) if operation_id && !operation_id.empty?

      "#{http_method}_#{path.gsub(/[{}]/, "").split("/").reject(&:empty?).join("_")}"
    end

    # Параметры пути в порядке объявления; подставляются в шаблон адреса.
    # @return [Array<Hash>] параметры пути в порядке появления
    def path_parameters
      parameters.select { |param| param[:in] == "path" }
    end

    # Параметры строки запроса. Заполняются только обязательные.
    # @return [Array<Hash>]
    def query_parameters
      parameters.select { |param| param[:in] == "query" }
    end

    # Параметры-заголовки; среди них распознаются идемпотентность и подпись webhook.
    # @return [Array<Hash>]
    def header_parameters
      parameters.select { |param| param[:in] == "header" }
    end

    # Схема успешного ответа: наименьший код из диапазона 2xx.
    # @return [Hash, nil] { description:, schema: } или nil, если ответа 2xx нет
    def success_response
      code = responses.keys.select { |key| key.to_s.start_with?("2") }.min
      responses[code]
    end

    # Коды ошибок, описанные провайдером у этой операции.
    # @return [Array<Integer>] по возрастанию
    def error_codes
      responses.keys.map(&:to_i).select { |code| code >= 400 }.sort
    end

    # Текст операции одной строкой; используется правилами и поиском ограничений.
    # @return [String]
    def text
      [summary, description].compact.join("\n")
    end

    private

    # @param value [String] имя в camelCase или kebab-case
    # @return [String] то же имя в snake_case
    def snake_case(value)
      value.gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .tr("-", "_")
           .downcase
    end
  end
end
