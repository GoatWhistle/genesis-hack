# frozen_string_literal: true

require_relative "meanings"
require_relative "result"
require_relative "text"

module Rsocket
  module Classify
    # Приём уведомлений: где подпись, чем подписано, какие поля читать.
    #
    # Ищем по строению, а не по имени: открытый метод, в теле которого лежат
    # поле события и поле статуса. Способ подписи в описаниях лежит текстом, а
    # не структурой, поэтому неизвестный алгоритм остаётся неизвестным —
    # проверять подпись наугад хуже, чем честно сказать, что не разобрали.
    class WebhookDetector
      def initialize(context)
        @spec = context.spec
        @meanings = Meanings.new(context.dictionaries.fields)
        @dictionary = context.dictionaries.webhook
      end

      def call
        operation = notification_operation
        return if operation.nil?

        WebhookInfo.new(
          operation: operation, signature_header: signature_header(operation),
          algorithm: algorithm(operation), event_field: field_name(operation, :event),
          status_field: field_name(operation, :status)
        )
      end

      private

      def notification_operation
        @spec.operations.find do |operation|
          operation.http_method == :post && operation.security.empty? && notification?(operation)
        end
      end

      def notification?(operation)
        %i[event status].all? do |meaning|
          @meanings.any?(operation.request_fields, meaning, deep: false)
        end
      end

      def field_name(operation, meaning)
        @meanings.find(operation.request_fields, meaning, deep: false)&.name
      end

      def signature_header(operation)
        @meanings.find(operation.header_params, :signature, deep: false)&.name
      end

      def algorithm(operation)
        text = [operation.summary, operation.description, header_description(operation)]
               .compact.join(" ").downcase
        found = Array(@dictionary["algorithms"]).find do |_name, words|
          words.any? { |word| text.include?(word.to_s.downcase) }
        end
        found ? found.first.to_sym : :unknown
      end

      def header_description(operation)
        @meanings.find(operation.header_params, :signature, deep: false)&.description
      end
    end
  end
end
