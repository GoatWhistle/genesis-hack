# frozen_string_literal: true

require_relative "../evidence"
require_relative "../meanings"

module Rsocket
  module Classify
    module Signals
      # Признак «по форме запроса и ответа».
      #
      # Главный из трёх: он работает там, где имена бесполезны. Провайдер волен
      # назвать создание перевода как угодно, но если в теле лежат сумма, валюта
      # и получатель, а в ответе — идентификатор и статус, то это создание, как
      # его ни назови.
      #
      # Правила — логика, поэтому живут в коде. Какое правило какую роль
      # подтверждает — знание, поэтому лежит в словаре ролей: роль перечисляет
      # имена правил, а этот класс их исполняет.
      class Signature
        SIGNAL = :signature

        RULES = %i[
          money_and_recipient_in_body identifier_in_path_status_in_response
          empty_body_on_subresource money_with_source_reference
          balance_in_response open_method_with_event_and_status
        ].freeze

        SUCCESS_CODES = (200..299)

        def initialize(context)
          @weights = context.dictionaries.weights["signature"] || {}
          @meanings = Meanings.new(context.dictionaries.fields)
        end

        def evidence(operation, role)
          (role.rules & RULES).filter_map { |rule| entry(rule, operation) }
        end

        private

        def entry(rule, operation)
          detail = send(rule, operation)
          return if detail.nil?

          Evidence.new(signal: SIGNAL, detail: detail, weight: weight(rule))
        end

        def weight(rule) = (@weights[rule.to_s] || 0.0).to_f

        # POST, в теле сумма, валюта и получатель, в ответе идентификатор и
        # статус — создание выплаты.
        def money_and_recipient_in_body(operation)
          return unless operation.http_method == :post
          return unless body_has?(operation, :currency) && creates_resource?(operation)

          amount = @meanings.find(operation.request_fields, :amount)
          recipient = @meanings.find(operation.request_fields, :recipient)
          return if amount.nil? || recipient.nil?

          "в теле запроса есть сумма «#{amount.path}», валюта и получатель " \
            "«#{recipient.path}», а в ответе — идентификатор и статус"
        end

        # GET с параметром в пути и статусом в ответе, без тела запроса —
        # запрос состояния.
        def identifier_in_path_status_in_response(operation)
          return unless operation.http_method == :get
          return if operation.path_params.empty? || operation.request_fields.any?

          status = @meanings.find(response_fields(operation), :status)
          return if status.nil?

          "GET с идентификатором в пути «#{path_parameters(operation)}» и статусом " \
            "«#{status.path}» в ответе, без тела запроса"
        end

        # POST или DELETE по адресу уже созданного ресурса с пустым или почти
        # пустым телом — действие над ним, а не создание нового.
        def empty_body_on_subresource(operation)
          return unless %i[post delete].include?(operation.http_method)
          return if operation.request_fields.size > 1
          return unless action_on_existing_resource?(operation)

          "#{operation.http_method.to_s.upcase} по адресу с идентификатором ранее созданного " \
            "ресурса «#{path_parameters(operation)}» и #{body_size(operation)} телом запроса"
        end

        # Сумма в теле есть, получателя нет, есть ссылка на исходную операцию —
        # возврат средств.
        def money_with_source_reference(operation)
          return unless operation.http_method == :post
          return if body_has?(operation, :recipient)

          amount = @meanings.find(operation.request_fields, :amount)
          source = @meanings.find(operation.request_fields, :source_reference)
          return if amount.nil? || source.nil?

          "в теле есть сумма «#{amount.path}» и ссылка на ранее созданную операцию " \
            "«#{source.path}», а получателя нет"
        end

        # GET без параметров, в ответе сумма и валюта — баланс.
        def balance_in_response(operation)
          return unless operation.http_method == :get
          return unless operation.path_params.empty? && operation.query_params.empty?

          balance = @meanings.find(response_fields(operation), :balance)
          return if balance.nil? || !response_has?(operation, :currency)

          "GET без параметров, в ответе сумма «#{balance.path}» и валюта"
        end

        # Метод объявлен открытым, в теле поле события и поле статуса — приём
        # уведомлений. Поля смотрим только на верхнем уровне: type внутри
        # получателя — это не тип события.
        def open_method_with_event_and_status(operation)
          return unless operation.http_method == :post && operation.security.empty?

          event = @meanings.find(operation.request_fields, :event, deep: false)
          status = @meanings.find(operation.request_fields, :status, deep: false)
          return if event.nil? || status.nil?

          "метод объявлен открытым, в теле есть поле события «#{event.path}» и поле " \
            "статуса «#{status.path}»"
        end

        def body_has?(operation, meaning) = @meanings.any?(operation.request_fields, meaning)

        def response_has?(operation, meaning) = @meanings.any?(response_fields(operation), meaning)

        def creates_resource?(operation)
          response_has?(operation, :identifier) && response_has?(operation, :status)
        end

        def action_on_existing_resource?(operation)
          return false if operation.path_params.empty?

          operation.http_method == :delete || subresource?(operation.path)
        end

        # Адрес вида /ресурс/{идентификатор}/действие: за идентификатором есть
        # ещё один шаг, значит это действие над существующим ресурсом.
        def subresource?(path)
          segments = path.split("/")
          index = segments.index { |segment| segment.start_with?("{") }
          !index.nil? && index < segments.length - 1
        end

        def response_fields(operation)
          operation.responses.filter_map do |code, response|
            response.fields if code.is_a?(Integer) && SUCCESS_CODES.cover?(code)
          end.flatten
        end

        def path_parameters(operation) = operation.path_params.map(&:name).join(", ")

        def body_size(operation) = operation.request_fields.empty? ? "пустым" : "почти пустым"
      end
    end
  end
end
