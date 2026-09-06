# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Parsing
      # Сырое описание API → модели: $ref раскрыты, allOf объединены. Понимает
      # OpenAPI 3.x (paths, webhooks, callbacks) и Swagger 2.0 (приводится к той же
      # форме через Swagger2Normalizer до разбора).
      class SpecParser
        SUPPORTED_OPENAPI = "3"

        # @param document [Hash] сырое описание OpenAPI или Swagger 2.0, ключи символами
        # @raise [ArgumentError] описание не OpenAPI/Swagger, версия не поддержана,
        #   либо в нём нет ни paths, ни webhooks
        def initialize(document)
          ensure_supported(document)
          @document = swagger2?(document) ? Swagger2Normalizer.new(document).call : document
          @resolver = SchemaResolver.new(@document)
        end

        # @return [Models::ApiSpec] описание в том виде, в каком его читают правила
        def call
          Models::ApiSpec.new(
            title: @document.dig(:info, :title).to_s,
            description: [@document.dig(:info, :summary),
                          @document.dig(:info, :description)].compact.join("\n"),
            version: @document.dig(:info, :version).to_s,
            servers: parse_servers,
            security_schemes: parse_security_schemes,
            operations: OperationParser.new(@document, @resolver).call,
            schemas: @document.dig(:components, :schemas) || {}
          )
        end

        private

        # @param document [Hash]
        # @return [Boolean]
        def swagger2?(document) = document[:swagger].to_s.start_with?("2")

        # Разбор не должен молча превращаться в пустой список операций: непонятный
        # документ или неподдержанная версия называются словами сразу. Ключ версии
        # необязателен сам по себе — важно лишь то, что если он назван, то верно.
        # @param document [Hash]
        # @return [void]
        # @raise [ArgumentError]
        def ensure_supported(document)
          if unsupported_version?(document)
            raise ArgumentError, "версия не поддержана: #{version_of(document)}"
          end
          return if document[:paths] || document[:webhooks]

          raise ArgumentError, "описание не OpenAPI/Swagger: нет ни paths, ни webhooks"
        end

        # @param document [Hash]
        # @return [Boolean] версия названа явно, но это не OpenAPI 3.x и не Swagger 2.0
        def unsupported_version?(document)
          return !document[:openapi].to_s.start_with?(SUPPORTED_OPENAPI) if document[:openapi]
          return !swagger2?(document) if document[:swagger]

          false
        end

        # @param document [Hash]
        # @return [String]
        def version_of(document) = (document[:openapi] || document[:swagger]).to_s

        # @return [Array<Models::ApiSpec::Server>]
        def parse_servers
          Array(@document[:servers]).map do |server|
            Models::ApiSpec::Server.new(url: server[:url], description: server[:description])
          end
        end

        # @return [Array<Models::ApiSpec::SecurityScheme>]
        def parse_security_schemes
          (@document.dig(:components, :securitySchemes) || {}).map do |name, body|
            Models::ApiSpec::SecurityScheme.new(
              name: name.to_s, type: body[:type], location: body[:in],
              parameter: body[:name], scheme: body[:scheme]
            )
          end
        end
      end
    end
  end
end
