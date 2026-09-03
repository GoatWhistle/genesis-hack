# frozen_string_literal: true

require "faraday"
require "json"

require_relative "provider/errors"

# HTTP-клиент, через который сгенерированный сервис ходит к провайдеру.
#
# Откуда взято: в примере из задания вызовы выглядят как
# `client.post(url, json: payload, headers: auth_headers)` и `client.get(url)`,
# а результат читается как `response.body["status"]`. Отсюда интерфейс: два
# метода, тело задаётся ключом `json:`, тело ответа приходит уже разобранным.
#
# Пространство имён здесь наше, в отличие от `Operation`: конкретного клиента
# заказчик в задании не называет, это наша деталь реализации, и занимать под
# неё имя верхнего уровня незачем.
class Provider
  class HttpClient
    # Ответ провайдера в том виде, в котором его читает сервис.
    Response = Data.define(:status, :body, :headers) do
      def success?
        status.between?(200, 299)
      end
    end

    # Код ответа → класс ошибки. Всё, чего здесь нет и что не 5xx, возвращается
    # сервису обычным ответом: например, 409 у идемпотентного повтора — это не
    # сбой, а тот же ресурс, и решать по нему должен сервис, а не транспорт.
    ERROR_CLASSES = {
      400 => Provider::ValidationError,
      401 => Provider::UnauthorizedError,
      402 => Provider::InsufficientBalanceError,
      403 => Provider::UnauthorizedError,
      422 => Provider::ValidationError,
      429 => Provider::RateLimitError
    }.freeze

    # Где в теле ответа лежит код ошибки провайдера. Это самая
    # распространённая раскладка, но не единственная, поэтому она не зашита:
    # сервис, собранный по спецификации с другим конвертом, передаёт свой путь.
    DEFAULT_ERROR_CODE_PATH = %w[error code].freeze

    # Заголовок с задержкой перед повтором: провайдеры описывают его у ответа
    # 429. Там, где его нет, `retry_after` останется пустым.
    RETRY_AFTER_HEADER = "retry-after"

    OPEN_TIMEOUT = 5
    TIMEOUT = 15

    def initialize(error_code_path: DEFAULT_ERROR_CODE_PATH, connection: nil)
      @error_code_path = error_code_path
      @connection = connection
    end

    def post(url, json: nil, headers: {})
      request(:post, url, headers: headers, body: json)
    end

    def get(url, headers: {})
      request(:get, url, headers: headers)
    end

    private

    def connection
      @connection ||= Faraday.new do |faraday|
        faraday.options.open_timeout = OPEN_TIMEOUT
        faraday.options.timeout = TIMEOUT
      end
    end

    def request(method, url, headers:, body: nil)
      raw = connection.public_send(method, url) do |request|
        request.headers["Content-Type"] = "application/json" if body
        request.headers.update(headers)
        request.body = JSON.generate(body) if body
      end
      handle(raw)
    end

    def handle(raw)
      body = parse(raw.body)
      headers = normalize_headers(raw.headers)
      raise error_for(raw.status, body, headers) if error?(raw.status)

      Response.new(status: raw.status, body: body, headers: headers)
    end

    def error?(status)
      ERROR_CLASSES.key?(status) || status >= 500
    end

    def error_for(status, body, headers)
      klass = ERROR_CLASSES.fetch(status, Provider::InternalError)
      klass.new(
        status: status,
        provider_code: body.is_a?(Hash) ? body.dig(*@error_code_path) : nil,
        body: body,
        retry_after: retry_after(headers)
      )
    end

    # Тело разбираем мягко: провайдер, отвечающий на ошибку страницей вместо
    # JSON, не должен превращаться в трассировку стека вместо понятного отказа.
    def parse(body)
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      { "raw" => body }
    end

    def normalize_headers(headers)
      headers.to_h.transform_keys { |key| key.to_s.downcase }
    end

    def retry_after(headers)
      value = headers[RETRY_AFTER_HEADER]
      value&.to_i
    end
  end
end
