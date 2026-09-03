# frozen_string_literal: true

module Rsocket
  module Generate
    # Переводы между тремя словарями: каноническим набором классификатора,
    # тремя статусами заказчика и кодами ответа HTTP.
    #
    # Почему перевод живёт здесь, а не в классификаторе: классификатор
    # описывает мир провайдеров и держит набор шире, чем нужно заказчику
    # (`created`, `refunded`, `needs_review` и прочее). Сузить его до трёх
    # значений — задача того, кто собирает код под конкретный контракт, то
    # есть генератора. Так классификатор не теряет смысл, а сервис получает
    # ровно то, что от него ждут.
    module Translation
      IN_PROGRESS = "in_progress"
      APPROVED = "approved"
      REJECTED = "rejected"

      # Во сколько раз минорная единица меньше основной. Сотня покрывает
      # рубли, доллары и евро; провайдеров с другим делителем в наших
      # описаниях нет, и когда появятся — значение придёт от классификатора.
      MINOR_UNIT_FACTOR = 100

      # Канонический статус классификатора → статус операции у заказчика.
      #
      # `refunded` сведён к отказу осознанно: для выплаты возврат средств
      # означает, что деньги до получателя не дошли. `needs_review` оставляет
      # операцию в работе — до решения человека она не завершена.
      CANONICAL_TO_CUSTOMER = {
        created: IN_PROGRESS,
        processing: IN_PROGRESS,
        needs_review: IN_PROGRESS,
        succeeded: APPROVED,
        rejected: REJECTED,
        cancelled: REJECTED,
        refunded: REJECTED
      }.freeze

      # Класс ошибки от классификатора → что с ней делать. Уходит и в код, и
      # в таблицу обработки ошибок в INTEGRATION.md.
      KLASS_TO_ACTION = {
        retryable: :retry_later,
        limit: :retry_backoff,
        auth: :alert,
        validation: :reject,
        final: :reject
      }.freeze

      # Код ответа провайдера → статус, с которым сервис отказывает наверх.
      HTTP_TO_STATUS = {
        400 => :unprocessable_entity,
        401 => :unauthorized,
        402 => :payment_required,
        403 => :unauthorized,
        404 => :not_found,
        409 => :conflict,
        422 => :unprocessable_entity,
        429 => :too_many_requests
      }.freeze

      UNKNOWN_HTTP_STATUS = :bad_gateway
      SERVER_ERROR_STATUS = :internal_server_error

      # Запасной класс ошибки по одному коду ответа. Используется, только
      # когда классификации нет: она уточняет класс по коду ошибки самого
      # провайдера и по словам в описании, и её вывод всегда важнее этого.
      DEFAULT_KLASS = {
        400 => :validation, 401 => :auth, 402 => :retryable, 403 => :auth,
        404 => :final, 408 => :retryable, 409 => :final, 422 => :validation, 429 => :limit
      }.freeze

      # Неизвестный статус провайдера не имеет права стать успехом или
      # отказом: операция остаётся в работе, и с ней разбирается человек.
      def self.customer_status(canonical)
        CANONICAL_TO_CUSTOMER.fetch(canonical&.to_sym, IN_PROGRESS)
      end

      def self.action(klass)
        KLASS_TO_ACTION.fetch(klass&.to_sym, :retry_alert)
      end

      def self.http_status(code)
        return SERVER_ERROR_STATUS if code >= 500

        HTTP_TO_STATUS.fetch(code, UNKNOWN_HTTP_STATUS)
      end

      def self.default_klass(code)
        return :retryable if code >= 500

        DEFAULT_KLASS.fetch(code, :final)
      end
    end
  end
end
