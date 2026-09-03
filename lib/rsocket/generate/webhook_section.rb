# frozen_string_literal: true

require_relative "field_matcher"

module Rsocket
  module Generate
    # Часть контекста, отвечающая за уведомления провайдера.
    #
    # Уведомления есть далеко не у всех: у провайдера с опросом статуса их
    # нет вовсе, и тогда весь раздел пуст. Шаблон обязан пережить оба случая,
    # а не выдумывать обработчик там, где принимать нечего.
    class WebhookSection
      def initialize(info)
        @info = info
      end

      def to_h
        return { signature: nil } if @info.nil?

        {
          signature: { header: @info.signature_header, algorithm: algorithm },
          webhook_event_field: @info.event_field,
          webhook_id_field: id_field
        }
      end

      # Значения событий, объявленные провайдером в перечислении поля события.
      def events
        field = fields.find { |candidate| candidate.name == @info&.event_field }
        field&.enum || []
      end

      private

      def algorithm
        @info.algorithm == :hmac_sha256 ? "SHA256" : nil
      end

      # Идентификатор выплаты внутри уведомления: у него своё имя, не такое,
      # как в ответе на создание.
      def id_field
        matcher = FieldMatcher.default
        fields.find { |field| matcher.role?(field.name, :provider_id) }&.name
      end

      def fields
        operation = @info&.operation
        operation ? operation.request_fields : []
      end
    end
  end
end
