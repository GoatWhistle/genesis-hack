# frozen_string_literal: true

require_relative "context_maps"
require_relative "field_matcher"
require_relative "endpoint_section"
require_relative "payload_section"
require_relative "webhook_section"
require_relative "response_plan"
require_relative "translation"
require_relative "service_context"

module Rsocket
  module Generate
    # Собирает контекст шаблона из разобранной спецификации и вывода
    # классификатора.
    #
    # Классификатор может отдать роль с вердиктом «не определено» или не
    # отдать её вовсе — это нормальный случай, а не сбой. Тогда контекст
    # остаётся без соответствующего адреса, шаблон честно пишет заглушку с
    # пометкой, а причина уходит в заметки.
    class ContextBuilder
      ROLES = { create: :create_payout, status: :fetch_status, cancel: :cancel }.freeze

      def initialize(spec, provider:, classification: nil)
        @spec = spec
        @classification = classification
        @provider = FieldMatcher.normalize(provider)
        @notes = []
      end

      def call
        ServiceContext.new(**identity, **endpoints, **maps, **payload, **response, **webhook,
                           notes: @notes + Array(@maps_builder&.notes))
      end

      private

      def identity
        {
          provider: @provider, class_name: class_name, env_prefix: env_prefix,
          title: @spec.title, version: @spec.version,
          base_url: base_url, base_url_env: "#{env_prefix}_BASE_URL",
          api_key_env: "#{env_prefix}_API_KEY", secret_env: "#{env_prefix}_CALLBACK_SECRET",
          minor_units: minor_units?
        }
      end

      def class_name
        "#{@provider.split("_").map(&:capitalize).join}Service"
      end

      def env_prefix
        @provider.upcase
      end

      # Песочница предпочтительнее: сгенерированный код не должен по
      # умолчанию ходить в боевой контур.
      def base_url
        server = @spec.servers.find { |s| s.env == :sandbox } || @spec.servers.first
        server&.url
      end

      def endpoints
        EndpointSection.new(
          { create: operation(:create), status: operation(:status),
            cancel: operation(:cancel) },
          schemes: @spec.security_schemes, minor_units: minor_units?
        ).to_h
      end

      def maps
        @maps_builder = ContextMaps.new(@classification, response_plan,
                                        webhook_events: webhook_events)
        {
          status_map: @maps_builder.status_map, error_map: @maps_builder.error_map,
          event_map: @maps_builder.event_map
        }
      end

      def response_plan
        @response_plan ||= ResponsePlan.new([operation(:create), operation(:status)])
      end

      def response
        {
          response_id_path: response_plan.id_path || ["id"],
          response_status_path: response_plan.status_path || ["status"],
          error_code_path: response_plan.error_code_path || %w[error code]
        }
      end

      def payload
        section = PayloadSection.new(operation(:create), minor_units: minor_units?)
        @notes.concat(section.notes)
        section.to_h
      end

      def webhook
        webhook_section.to_h
      end

      def webhook_events
        webhook_section.events
      end

      def webhook_section
        @webhook_section ||= WebhookSection.new(@classification&.webhook)
      end

      def minor_units?
        @classification&.money.nil? || @classification.money.unit == :minor
      end

      def operation(kind)
        assignment = @classification&.roles&.dig(ROLES.fetch(kind))
        return nil if assignment.nil? || assignment.verdict == :unknown

        assignment.operation
      end
    end
  end
end
