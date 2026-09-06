# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Parsing
      # Сырое описание API → модели: $ref раскрыты, allOf объединены.
      class SpecParser
        HTTP_METHODS = %w[get post put patch delete].freeze
        JSON_CONTENT = %i[application/json application/problem+json].freeze

        # @param document [Hash] сырое описание OpenAPI, ключи символами
        def initialize(document)
          @document = document
          @resolver = SchemaResolver.new(document)
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
            operations: parse_operations,
            schemas: @document.dig(:components, :schemas) || {}
          )
        end

        private

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

        # Операции всех путей одним списком; параметры уровня пути добавляются каждой.
        # @return [Array<Models::ApiOperation>]
        def parse_operations
          (@document[:paths] || {}).flat_map do |path, node|
            shared = Array(node[:parameters])
            node.slice(*HTTP_METHODS.map(&:to_sym)).map do |verb, body|
              build_operation(path.to_s, verb, body, shared)
            end
          end
        end

        # @param path [String] шаблон пути
        # @param verb [Symbol] глагол HTTP
        # @param body [Hash] тело операции из описания
        # @param shared [Array<Hash>] параметры, объявленные на уровне пути
        # @return [Models::ApiOperation]
        def build_operation(path, verb, body, shared)
          Models::ApiOperation.new(
            operation_id: body[:operationId], http_method: verb, path: path,
            summary: body[:summary], description: body[:description],
            tags: Array(body[:tags]).map(&:to_s), **operation_details(body, shared)
          )
        end

        # @param body [Hash] тело операции
        # @param shared [Array<Hash>] параметры уровня пути
        # @return [Hash] параметры, схема запроса, ответы и требования авторизации
        def operation_details(body, shared)
          {
            parameters: parse_parameters(shared + Array(body[:parameters])),
            request: request_body(body[:requestBody]),
            responses: parse_responses(body[:responses]),
            security: body[:security] || @document[:security]
          }
        end

        # @param raw [Array<Hash>] параметры вперемешку с $ref
        # @return [Array<Hash>] { name:, in:, required:, description:, schema: }
        def parse_parameters(raw)
          raw.map { |parameter| @resolver.call(parameter) }.compact.map do |parameter|
            {
              name: parameter[:name].to_s,
              in: parameter[:in].to_s,
              required: parameter[:required] == true,
              description: parameter[:description].to_s,
              schema: parameter[:schema]
            }
          end
        end

        # @param raw [Hash, nil] requestBody операции
        # @return [Hash] { schema:, example: }
        def request_body(raw)
          body = @resolver.call(raw)
          return { schema: nil, example: nil } if body.nil?

          json_body(body[:content])
        end

        # @param responses [Hash, nil] ответы операции
        # @return [Hash{String => Hash}] код → { description:, schema:, example: }
        def parse_responses(responses)
          (responses || {}).to_h do |code, body|
            resolved = @resolver.call(body) || {}
            [code.to_s,
             { description: resolved[:description].to_s, **json_body(resolved[:content]) }]
          end
        end

        # Тело берётся в JSON; без него — первый описанный тип.
        # @param content [Hash, nil] секция content
        # @return [Hash] схема выбранного типа и пример, если провайдер его привёл
        def json_body(content)
          media = json_content(content)
          { schema: @resolver.call(media&.dig(:schema)), example: example_of(media) }
        end

        # @param content [Hash, nil] секция content
        # @return [Hash, nil] описание выбранного типа содержимого целиком
        def json_content(content)
          return nil if content.nil?

          key = JSON_CONTENT.find { |name| content.key?(name) } || content.keys.first
          content[key]
        end

        # Пример из описания приоритетен для фикстур.
        # @param media [Hash, nil] описание типа содержимого
        # @return [Object, nil] пример из example или первый из examples
        def example_of(media)
          return nil unless media.is_a?(Hash)
          return media[:example] if media.key?(:example)

          first = Array(media[:examples]&.values).first
          first.is_a?(Hash) ? first[:value] : nil
        end
      end
    end
  end
end
