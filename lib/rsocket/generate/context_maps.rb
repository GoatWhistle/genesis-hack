# frozen_string_literal: true

require_relative "translation"

module Rsocket
  module Generate
    # Карты статусов, ошибок и событий для сгенерированного сервиса.
    #
    # Источник истины — вывод классификатора. Там, где его нет, карта
    # собирается из того, что прямо написано в спецификации, а всё, чего не
    # хватило, уходит заметкой в отчёт. Пустая карта статусов лучше
    # выдуманной: сервис оставит операцию в работе, а не признает выплату
    # успешной по незнакомому слову.
    class ContextMaps
      def initialize(classification, response_plan, webhook_events: [])
        @classification = classification
        @response_plan = response_plan
        @webhook_events = webhook_events
        @notes = []
      end

      attr_reader :notes

      # Статус провайдера → статус операции у заказчика.
      def status_map
        @status_map ||= build_status_map
      end

      # Код ответа → код ошибки у нас, статус отказа и что с ошибкой делать.
      def error_map
        @error_map ||= build_error_map
      end

      # Событие уведомления → статус операции у заказчика.
      #
      # Имя события почти всегда содержит статус: `payout.completed`,
      # `transfer_failed`. Берём последнее слово имени и ищем его в карте
      # статусов — так событие переводится тем же словарём, что и статус, и
      # две карты не могут разъехаться.
      def event_map
        @event_map ||= @webhook_events.to_h { |event| [event, status_map[last_word(event)]] }
                                      .compact
      end

      private

      def build_status_map
        mappings = Array(@classification&.statuses)
        return classified_statuses(mappings) if mappings.any?

        declared = @response_plan.provider_statuses
        @notes << "статусы провайдера не классифицированы: #{declared.join(", ")}" if declared.any?
        {}
      end

      def classified_statuses(mappings)
        mappings.to_h do |mapping|
          [mapping.provider_value, Translation.customer_status(mapping.canonical)]
        end
      end

      def build_error_map
        mappings = Array(@classification&.errors)
        return mappings.to_h { |m| [m.http_code, entry(m.http_code, m.provider_code, m.klass)] } if
          mappings.any?

        @notes << "ошибки провайдера не классифицированы, класс определён по коду ответа"
        @response_plan.error_codes.to_h { |code| [code, entry(code, nil, nil)] }
      end

      # Код ошибки берётся у провайдера. Если он его не объявил, вместо
      # класса ошибки подставляется имя состояния HTTP: «provider.conflict»
      # понятно дежурному, а «provider.final» не говорит ему ничего.
      def entry(http_code, provider_code, klass)
        klass ||= Translation.default_klass(http_code)
        status = Translation.http_status(http_code)
        {
          code: "provider.#{provider_code || status}",
          status: status,
          action: Translation.action(klass)
        }
      end

      def last_word(event)
        event.to_s.split(/[^a-zA-Z0-9]+/).last.to_s
      end
    end
  end
end
