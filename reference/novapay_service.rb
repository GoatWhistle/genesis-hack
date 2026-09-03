# frozen_string_literal: true

require "bigdecimal"
require "openssl"

# В приложении заказчика `Provider::BaseService` подгружается автоматически.
# У нас его роль играет документированная заглушка контракта из
# lib/rsocket/runtime/ — без неё этот файл нельзя ни запустить, ни проверить,
# поэтому она подключается явно.
require_relative "../lib/rsocket/runtime"

# Интеграция с NovaPay, написанная руками.
#
# Это образец, а не результат генерации. Он существует, чтобы сначала получить
# код, который не стыдно показать Ruby-инженеру, и только потом научить
# генератор его воспроизводить. Обратный порядок — сперва генератор, потом
# «посмотрим, что вышло» — даёт машинную кашу, которую мы не отличим от
# нормального кода.
#
# Отсюда правило: подстановок вида ERB здесь нет и быть не должно. Это живой
# Ruby. Шаблон родится из него отдельной задачей.
#
# Собрано по provider_api.yaml от организаторов и по канону, подтверждённому
# экспертом 3 сентября: сумма в копейках, `bank_code` обязателен при выплате
# через СБП, подпись уведомления — HMAC-SHA256 от сырого тела в hex.
class Provider
  class NovapayService < BaseService
    # Всё, что вычитано из спецификации провайдера, собрано в одном месте.
    #
    # Разделение не косметическое. Ниже, в самом классе, лежит механизм: он
    # одинаков для любого провайдера. Здесь — знание: адреса, заголовки,
    # карты статусов и ошибок, то есть ровно то, что меняется от провайдера к
    # провайдеру. Когда из этого файла родится шаблон, генератор будет
    # заполнять этот модуль, а тела методов останутся нетронутыми.
    module Contract
      BASE_URL = ENV.fetch("NOVAPAY_BASE_URL", "https://api.sandbox.novapay.example/v1")

      # ЗАПОЛНИТЬ ВРУЧНУЮ. Ключа и секрета в спецификации нет и быть не может —
      # провайдер выдаёт их при подключении. Читаются в момент вызова, а не при
      # загрузке файла: иначе значение застынет на момент старта процесса.
      API_KEY_ENV = "NOVAPAY_API_KEY"
      CALLBACK_SECRET_ENV = "NOVAPAY_CALLBACK_SECRET"

      API_KEY_HEADER = "X-API-Key"
      IDEMPOTENCY_HEADER = "Idempotency-Key"
      SIGNATURE_HEADER = "X-NovaPay-Signature"
      SIGNATURE_ALGORITHM = "SHA256"

      CREATE_PATH = "/payouts"
      STATUS_PATH = "/payouts/%<payout_id>s"

      # Ответ 409 у NovaPay — не сбой, а повтор по ключу идемпотентности:
      # возвращается та же выплата. Поэтому он разбирается наравне с 201.
      DUPLICATE_STATUS = 409

      # Сумма приходит в рублях, а провайдер ждёт копейки.
      MINOR_UNIT_FACTOR = 100
      # Минимальная сумма выплаты — 1000 RUB, в спецификации записана как
      # `minimum: 100000` копеек и продублирована словами в описании метода.
      MINIMUM_AMOUNT = 1000

      DEFAULT_CURRENCY = "RUB"

      # Способы выплаты из перечисления `Recipient.type` в спецификации.
      RECIPIENT_TYPES = %w[sbp card].freeze
      # Поля реквизитов, которые провайдер принимает для каждого способа.
      RECIPIENT_FIELDS = {
        "sbp" => %w[phone bank_code bank_name],
        "card" => %w[phone card_number]
      }.freeze

      # Условно обязательные поля: поле → способ выплаты, при котором оно
      # обязательно. В спецификации это записано словами в описании поля
      # («обязателен для type=sbp»), а не структурой, поэтому автоматически
      # такое не вычитывается. Эксперт 3 сентября назвал `required_if` как раз
      # тем общим механизмом, которым подобные условия и надо выражать.
      CONDITIONALLY_REQUIRED = { "bank_code" => "sbp" }.freeze

      # `request_method` — логический тип действия шлюза, а не HTTP-глагол
      # (уточнено экспертом 3 сентября). Для NovaPay он задаёт способ выплаты;
      # значение по умолчанию означает «взять способ из реквизитов операции».
      REQUEST_METHOD_TYPES = { "sbp_payout" => "sbp", "card_payout" => "card" }.freeze
      # Типы действия, при которых проверяются условия выплаты. Для `status` и
      # `check` они не нужны: там ничего не отправляется.
      PAYOUT_REQUEST_METHODS = %w[create sbp_payout card_payout].freeze

      # Статус провайдера → статус операции у заказчика.
      STATUS_MAP = {
        "pending" => BaseService::IN_PROGRESS,
        "processing" => BaseService::IN_PROGRESS,
        "completed" => BaseService::APPROVED,
        "failed" => BaseService::REJECTED,
        "cancelled" => BaseService::REJECTED
      }.freeze

      # Событие уведомления → статус операции у заказчика.
      EVENT_MAP = {
        "payout.completed" => BaseService::APPROVED,
        "payout.processing" => BaseService::IN_PROGRESS,
        "payout.failed" => BaseService::REJECTED,
        "payout.cancelled" => BaseService::REJECTED
      }.freeze

      # Код ответа провайдера → наш код ошибки, статус ответа и что с ней
      # делать. Действие уходит в INTEGRATION.md: по нему видно, имеет ли
      # смысл повтор.
      ERROR_MAP = {
        400 => { code: "provider.validation_error", status: :unprocessable_entity,
                 action: :reject },
        401 => { code: "provider.invalid_credentials", status: :unauthorized, action: :alert },
        402 => { code: "provider.insufficient_balance", status: :payment_required,
                 action: :retry_later },
        404 => { code: "provider.payout_not_found", status: :not_found, action: :reject },
        422 => { code: "provider.validation_error", status: :unprocessable_entity,
                 action: :reject },
        429 => { code: "provider.rate_limit", status: :too_many_requests,
                 action: :retry_backoff },
        500 => { code: "provider.internal_error", status: :internal_server_error,
                 action: :retry_alert }
      }.freeze

      UNKNOWN_ERROR = { code: "provider.unknown_error", status: :bad_gateway,
                        action: :retry_alert }.freeze
    end

    # Сборка тела запроса из операции заказчика.
    #
    # Вынесено отдельно по той же причине, что и `Contract`: это самая
    # провайдерозависимая часть файла. Названия полей, вложенность, единицы
    # суммы — всё здесь, и всё берётся из спецификации.
    module Payload
      include Contract

      private

      def build_payout_payload(operation, request_method)
        {
          amount: to_minor_units(operation.amount),
          currency: operation.currency || DEFAULT_CURRENCY,
          external_id: operation.id,
          recipient: build_recipient(operation, request_method)
        }
      end

      def build_recipient(operation, request_method)
        type = recipient_type(operation, request_method)
        requisite = operation.payout_requisite[type] || {}
        filled = RECIPIENT_FIELDS.fetch(type, []).reject { |field| blank?(requisite[field]) }
        { type: type }.merge(filled.to_h { |field| [field.to_sym, requisite[field]] })
      end

      def recipient_type(operation, request_method)
        REQUEST_METHOD_TYPES[request_method.to_s] ||
          RECIPIENT_TYPES.find { |type| operation.payout_requisite.key?(type) } ||
          RECIPIENT_TYPES.first
      end

      # Сумма переводится через BigDecimal, а не умножением числа с плавающей
      # точкой: `(19.99 * 100).to_i` даёт 1998, и такая ошибка в выплатах
      # находится не сразу и стоит дорого.
      def to_minor_units(amount)
        (BigDecimal(amount.to_s) * MINOR_UNIT_FACTOR).round
      end
    end

    include Contract
    include Payload

    # Предпроверки до обращения к провайдеру.
    def check_conditions(operation, request_method)
      base_result = super
      return base_result if base_result.failed?
      return success unless PAYOUT_REQUEST_METHODS.include?(request_method.to_s)
      return failure(:unprocessable_entity, "amount_too_low") if operation.amount < MINIMUM_AMOUNT

      missing = missing_conditional_field(operation)
      return failure(:unprocessable_entity, "#{missing}_required") if missing

      success
    end

    # Создание выплаты.
    def create_request(operation, request_method = "create")
      response = client.post(
        "#{BASE_URL}#{CREATE_PATH}",
        json: build_payout_payload(operation, request_method),
        headers: create_headers(operation)
      )
      parse_create_response(operation, response)
    rescue Provider::ApiError => e
      provider_failure(e)
    end

    # Запрос статуса выплаты.
    def fetch_status(operation)
      path = format(STATUS_PATH, payout_id: operation.provider_operation_id)
      response = client.get("#{BASE_URL}#{path}", headers: auth_headers)
      return failure(:not_found, "provider.payout_not_found") unless response.success?

      parse_status_response(response.body)
    rescue Provider::ApiError => e
      provider_failure(e)
    end

    # Обработка уведомления о смене статуса.
    def process_callback(payload)
      return failure(:unauthorized, "provider.invalid_signature") unless valid_signature?(payload)

      operation_status = EVENT_MAP[payload["event"]]
      return failure(:unprocessable_entity, "unknown_event") if operation_status.nil?

      apply_callback(payload, operation_status)
    end

    private

    def auth_headers
      { API_KEY_HEADER => ENV.fetch(API_KEY_ENV) }
    end

    # Ключ идемпотентности защищает от двойной выплаты при повторе запроса.
    # Берётся идентификатор операции: он не меняется между повторами, а
    # случайное значение сделало бы заголовок бесполезным.
    def create_headers(operation)
      auth_headers.merge(IDEMPOTENCY_HEADER => operation.id.to_s)
    end

    # Первое незаполненное условно обязательное поле — или nil, если все на
    # месте. Проверяется только тот способ выплаты, которым операция и идёт:
    # отсутствие БИКа в реквизитах карты никого не касается.
    def missing_conditional_field(operation)
      found = CONDITIONALLY_REQUIRED.find do |field, type|
        requisite = operation.payout_requisite[type]
        requisite && blank?(requisite[field])
      end
      found&.first
    end

    def parse_create_response(operation, response)
      body = response.body
      operation.provider_operation_id = body["id"]
      success(
        provider_operation_id: body["id"],
        operation_status: map_status(body["status"]),
        provider_status: body["status"],
        duplicate: response.status == DUPLICATE_STATUS
      )
    end

    def parse_status_response(body)
      success(
        provider_operation_id: body["id"],
        operation_status: map_status(body["status"]),
        provider_status: body["status"]
      )
    end

    # Неизвестный статус не имеет права стать `approved` или `rejected`:
    # операция остаётся в работе, и человек разбирается с ней сам. Молча
    # признать выплату успешной по незнакомому слову — худшее из возможного.
    def map_status(provider_status)
      STATUS_MAP.fetch(provider_status, IN_PROGRESS)
    end

    def provider_failure(error)
      mapping = ERROR_MAP.fetch(error.status, UNKNOWN_ERROR)
      failure(
        mapping[:status], mapping[:code],
        action: mapping[:action], provider_code: error.provider_code, retry_after: error.retry_after
      )
    end

    def apply_callback(payload, operation_status)
      payout_id = payload["payout_id"]
      details = { provider_status: payload["status"], event: payload["event"] }
      case operation_status
      when APPROVED then approve_operation(payout_id, **details)
      when REJECTED then reject_operation(payout_id, callback_error_code(payload), **details)
      else progress_operation(payout_id, **details)
      end
    end

    def callback_error_code(payload)
      payload.dig("error", "code")
    end

    # Подпись считается от сырого тела запроса секретом провайдера, результат
    # в hex. Сравнение — постоянного времени: обычное `==` выходит из цикла на
    # первом несовпавшем символе и по времени ответа выдаёт подпись по байту.
    def valid_signature?(payload)
      body = raw_body(payload)
      received = callback_header(payload, SIGNATURE_HEADER)
      return false if blank?(body) || blank?(received)

      expected = OpenSSL::HMAC.hexdigest(SIGNATURE_ALGORITHM, ENV.fetch(CALLBACK_SECRET_ENV), body)
      OpenSSL.secure_compare(expected, received)
    end
  end
end
