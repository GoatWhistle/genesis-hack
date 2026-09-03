# frozen_string_literal: true

require_relative "../ir"

module Rsocket
  module Spec
    class SecurityNormalizer
      LOCATIONS = %w[header query cookie].freeze

      attr_reader :notes

      def initialize(document, notes)
        @document = document
        @notes = notes
      end

      def schemes
        raw_schemes.map do |id, scheme|
          kind, location, name = details(scheme)
          note_unknown(id) if kind == :unknown
          build_scheme(id, scheme, kind, location, name)
        end
      end

      def names(security)
        Array(security).flat_map { |requirement| requirement.is_a?(Hash) ? requirement.keys : [] }
      end

      # Пустой список требований у операции по договорённости означает «метод
      # намеренно открыт». Когда в описании нет ни одной схемы авторизации,
      # такой же пустой список означает совсем другое — что про авторизацию
      # просто не написали. Молча выдавать это за открытый API нельзя.
      def note_undeclared_authentication(operations)
        return unless raw_schemes.empty?
        return if operations.any? { |operation| operation.security.any? }

        @notes << Rsocket::Ir::Note.new(
          level: :needs_confirmation,
          where: "components.securitySchemes",
          message: "В описании нет ни одной схемы авторизации: все операции выглядят " \
                   "открытыми. Если ключ или токен всё же нужен, задайте его вручную"
        )
      end

      private

      def raw_schemes
        @document.dig("components", "securitySchemes") || {}
      end

      def details(scheme)
        case scheme["type"]
        when "apiKey" then [:api_key, location(scheme["in"]), scheme["name"]]
        when "http" then http_details(scheme)
        when "oauth2" then [:oauth2, nil, nil]
        else [:unknown, nil, scheme["name"]]
        end
      end

      def http_details(scheme)
        kinds = { "bearer" => :bearer, "basic" => :basic }
        [kinds.fetch(scheme["scheme"]&.downcase, :unknown), :header, "Authorization"]
      end

      def location(value)
        value&.to_sym if LOCATIONS.include?(value)
      end

      def build_scheme(id, scheme, kind, location, name)
        Rsocket::Ir::SecurityScheme.new(
          id: id, kind: kind, location: location, name: name,
          description: scheme["description"]
        )
      end

      def note_unknown(id)
        @notes << Rsocket::Ir::Note.new(
          level: :needs_confirmation,
          where: "components.securitySchemes.#{id}",
          message: "Способ авторизации не распознан и требует ручной проверки"
        )
      end
    end
  end
end
