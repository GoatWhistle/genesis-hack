# frozen_string_literal: true

module Config
  # Структурный признак операции: не слово в названии, а форма запроса и ответа.
  # Имя операции провайдер выбирает как хочет, а сумму, получателя и статус он
  # обязан описать схемой — по ним и видно, чем операция занимается.
  class Signal
    # Глубина обхода схемы: дальше третьего уровня лежат детали адреса и банка.
    DEPTH = 3

    # Слова, по которым свойство схемы узнаётся. Списки нарочно шире словаря
    # payload_patterns: здесь важно не заполнить поле, а понять смысл операции.
    PROPERTIES = {
      amount: /\A(amount|sum|total|price|value|money)\w*\z/i,
      currency: /\A(currency|curr|ccy|asset|asset_?id|coin)\w*\z/i,
      recipient: /(recipient|beneficiar|payee|creditor|counterpart|destination|receiver|
                   payout_?method|credit_?account|to_?account|iban|bank_?account|card_?number|
                   card_?token|account_?number|wallet|msisdn|payment_?instrument)/xi,
      status: /\A(status|state|payment_?status|transfer_?status|payout_?status)\z/i,
      identifier: /\A(\w*_)?(id|token|reference|uuid|key)\z/i
    }.freeze

    # Признаки, которые умеет считать классификатор. Веса и набор задаёт base.yml.
    KINDS = %i[money_request recipient_request request_body status_response identifier_response
               id_in_path checkout_request].freeze

    attr_reader :kind, :weight

    # @param kind [String, Symbol] признак из KINDS
    # @param weight [Integer] очки за признак; отрицательный вес штрафует
    # @param veto [Boolean] снимать ли кандидата целиком при совпадении
    # @raise [ArgumentError] признак неизвестен
    def initialize(kind:, weight: 0, veto: false)
      raise ArgumentError, "неизвестный признак: #{kind}" unless KINDS.include?(kind.to_sym)

      @kind = kind.to_sym
      @weight = weight.to_i
      @veto = veto == true
    end

    # @return [Boolean] признак снимает кандидата, а не меняет его счёт
    def veto? = @veto

    # @param operation [Models::ApiOperation]
    # @return [Boolean]
    def matches?(operation)
      send(:"#{kind}?", operation)
    end

    # Правила отчёта спрашивают у сработавшего правила поле операции; у признака
    # поля нет — он смотрит на схему целиком.
    # @return [String]
    def field = "структура"

    # @return [String] представление для mapping.yml и отчёта
    def to_s = "признак #{kind}"

    private

    # @return [Boolean] в теле запроса есть сумма и валюта: так выглядит платёж
    def money_request?(operation)
      names = properties(operation.request_schema)
      match?(names, :amount) && match?(names, :currency)
    end

    # @return [Boolean] в теле запроса назван получатель или его реквизит
    def recipient_request?(operation)
      match?(properties(operation.request_schema), :recipient)
    end

    # Возврат плательщика из карточного checkout вместе с параметрами capture/MOTO
    # описывает приём платежа. Один return_url не доказывает направление денег.
    def checkout_request?(operation)
      names = properties(operation.request_schema)
      names.any? { |name| /\Areturn_?url\z/i.match?(name) } &&
        names.any? do |name|
          /\A(delayed_?capture|capture_?method|moto|prefilled_?cardholder_?details)\z/i.match?(name)
        end
    end

    # @return [Boolean] у операции вообще описано тело запроса
    def request_body?(operation) = !operation.request_schema.nil?

    # @return [Boolean] успешный ответ сообщает состояние операции
    def status_response?(operation)
      match?(properties(operation.success_response&.dig(:schema)), :status)
    end

    # @return [Boolean] успешный ответ возвращает идентификатор созданного
    def identifier_response?(operation)
      match?(properties(operation.success_response&.dig(:schema)), :identifier)
    end

    # @return [Boolean] адрес заканчивается параметром: обращение к одной операции
    def id_in_path?(operation) = /\{[^}]+\}\z/.match?(operation.path.to_s)

    # @param names [Array<String>] имена свойств схемы
    # @param kind [Symbol] ключ PROPERTIES
    # @return [Boolean]
    def match?(names, kind)
      pattern = PROPERTIES.fetch(kind)
      names.any? { |name| pattern.match?(name) }
    end

    # Имена свойств схемы вглубь до DEPTH: сумма нередко лежит объектом
    # { amount: { value:, currency: } }, а получатель — внутри destination.
    # @param schema [Hash, nil]
    # @param depth [Integer]
    # @return [Array<String>]
    def properties(schema, depth = 0)
      return [] unless schema.is_a?(Hash) && depth < DEPTH

      own = schema[:properties].is_a?(Hash) ? schema[:properties] : {}
      nested = own.values.flat_map { |value| properties(value, depth + 1) }
      items = properties(schema[:items], depth + 1)
      own.keys.map(&:to_s) + nested + items
    end
  end
end
