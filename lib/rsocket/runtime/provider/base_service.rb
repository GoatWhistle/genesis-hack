# frozen_string_literal: true

require_relative "errors"
require_relative "../http_client"

# Базовый класс интеграции из системы заказчика.
#
# Откуда взято: контракт приведён в задании дословно —
#
#   class Provider::ExampleService < Provider::BaseService
#     def check_conditions(operation, request_method)   # предпроверки
#     def create_request(operation, ...)                # создание выплаты
#     def process_callback(payload)                     # обработка webhook
#     def fetch_status(operation)                       # статус-запрос
#   end
#
# Сам класс нам не выдали: 3 сентября эксперт ответил, что «полный
# production-класс и harness не обязательны». Здесь наша реконструкция по
# примеру из задания. Она нужна не для вида — без неё сгенерированный сервис
# нельзя ни запустить, ни прогнать через поддельный сервер, то есть нельзя
# доказать, что он работает.
#
# Что восстановлено по примеру из задания и почему:
#
#   * `success` и `failure(status, code)` — видны в теле примера
#     (`failure(:too_many_requests, "provider.rate_limit")`);
#   * `base_result = super` и `base_result.failed?` в `check_conditions` —
#     значит, у базового класса есть своя реализация предпроверок, а результат
#     умеет отвечать на `failed?`;
#   * `approve_operation` и `reject_operation` — вызываются из
#     `process_callback` и переводят операцию в статус на нашей стороне;
#   * `client` — через него уходят `client.post` и `client.get`.
class Provider
  class BaseService
    # Статусы операции на стороне заказчика. В задании их ровно три, и любой
    # статус провайдера обязан свестись к одному из них.
    IN_PROGRESS = "in_progress"
    APPROVED = "approved"
    REJECTED = "rejected"

    # Поля операции, без которых обращаться к провайдеру бессмысленно.
    # Проверяются до запроса: отказ на нашей стороне дешевле отказа по сети.
    REQUIRED_OPERATION_FIELDS = %i[id amount currency payout_requisite].freeze

    # Служебные ключи, под которыми в `process_callback` приходят сырое тело
    # запроса и его заголовки.
    #
    # Зачем так. Подпись уведомления считается от сырого тела, а не от
    # разобранного хеша: пересборка JSON даёт другую строку — другой порядок
    # ключей, другие пробелы — и честная подпись перестаёт сходиться. Но
    # контракт из задания — `process_callback(payload)`, один аргумент, и
    # менять его нельзя. Поэтому тело и заголовки кладутся в тот же хеш под
    # служебными ключами: контракт сохранён, а подпись проверяется
    # по-настоящему. Как их туда положить, описано в INTEGRATION.md.
    RAW_BODY_KEY = "__raw_body"
    HEADERS_KEY = "__headers"

    # Результат работы метода сервиса.
    #
    # Одна форма на все четыре метода: и на успех, и на отказ. Вызывающей
    # стороне не приходится гадать, что именно вернулось — строка, символ или
    # исключение, — а сгенерированным тестам есть что сравнивать.
    Result = Data.define(:ok, :status, :code, :payload) do
      def initialize(**attributes)
        super(status: nil, code: nil, payload: {}, **attributes)
      end

      def success?
        ok
      end

      def failed?
        !ok
      end

      # Статус операции на стороне заказчика, если метод его определил.
      def operation_status
        payload[:operation_status]
      end
    end

    # История переводов операции в статусы заказчика.
    #
    # У заказчика `approve_operation` меняет запись в базе. Базы у нас нет,
    # поэтому заглушка запоминает переводы списком: по нему проверяльщик и
    # сгенерированные тесты видят, что уведомление действительно довело
    # операцию до нужного статуса, а не просто не упало.
    attr_reader :transitions

    def initialize(client: nil)
      @client = client
      @transitions = []
    end

    # Предпроверки перед обращением к провайдеру.
    #
    # `request_method` — логический тип действия (способ выплаты у шлюза либо
    # значения вроде `status` и `check`), а не HTTP-глагол. Уточнено экспертом
    # 3 сентября. Базовая реализация к нему безразлична: она проверяет саму
    # операцию, а условия конкретного провайдера добавляет наследник.
    def check_conditions(operation, _request_method = nil)
      missing = REQUIRED_OPERATION_FIELDS.find { |field| blank?(operation.public_send(field)) }
      return failure(:unprocessable_entity, "operation.#{missing}_missing") if missing
      return failure(:unprocessable_entity, "operation.amount_invalid") if operation.amount <= 0

      success
    end

    # Дальше — то, что обязан реализовать каждый провайдер. Заглушка не
    # притворяется, что умеет их выполнять: молчаливый `nil` в интеграции
    # платежей хуже громкого отказа.
    def create_request(_operation, _request_method = "create")
      raise NotImplementedError, "#{self.class}#create_request не реализован"
    end

    def fetch_status(_operation)
      raise NotImplementedError, "#{self.class}#fetch_status не реализован"
    end

    def process_callback(_payload)
      raise NotImplementedError, "#{self.class}#process_callback не реализован"
    end

    private

    def client
      @client ||= Provider::HttpClient.new
    end

    def success(**payload)
      Result.new(ok: true, status: :ok, code: nil, payload: payload)
    end

    def failure(status, code, **payload)
      Result.new(ok: false, status: status, code: code, payload: payload)
    end

    # Переводы операции в статусы заказчика. Возвращают тот же `Result`, что и
    # остальные методы, поэтому обработчик уведомления может просто вернуть
    # результат наружу.
    def approve_operation(provider_operation_id, **payload)
      transition(provider_operation_id, APPROVED, **payload)
    end

    def reject_operation(provider_operation_id, error_code = nil, **payload)
      transition(provider_operation_id, REJECTED, error_code: error_code, **payload)
    end

    def progress_operation(provider_operation_id, **payload)
      transition(provider_operation_id, IN_PROGRESS, **payload)
    end

    def transition(provider_operation_id, operation_status, **payload)
      record = { provider_operation_id: provider_operation_id, operation_status: operation_status }
      @transitions << record
      success(**record, **payload)
    end

    # Сырое тело уведомления — то, от чего считается подпись.
    def raw_body(payload)
      payload[RAW_BODY_KEY]
    end

    # Заголовок уведомления без оглядки на регистр: разные веб-серверы отдают
    # их по-разному, а подпись из-за этого теряться не должна.
    def callback_header(payload, name)
      headers = payload[HEADERS_KEY] || {}
      wanted = name.to_s.downcase
      _, value = headers.find { |key, _| key.to_s.downcase == wanted }
      value
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
