# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Parsing
      # Разбор операций описания: пути, webhooks и callbacks → Models::ApiOperation.
      # Webhooks и callbacks размечаются incoming: true — их присылает провайдер сам,
      # в отличие от операций paths, которые вызывает адаптер.
      class OperationParser
        HTTP_METHODS = %w[get post put patch delete].freeze
        JSON_CONTENT = %i[application/json application/problem+json].freeze

        # @param document [Hash] описание, уже приведённое к форме OpenAPI 3
        # @param resolver [SchemaResolver] тот же резолвер, что строит ApiSpec
        def initialize(document, resolver)
          @document = document
          @resolver = resolver
        end

        # @return [Array<Models::ApiOperation>]
        def call
          section_operations(@document[:paths], incoming: false) +
            section_operations(@document[:webhooks], incoming: true)
        end

        private

        # @param section [Hash, nil] paths или webhooks
        # @param incoming [Boolean] true для webhooks — их присылает провайдер
        # @return [Array<Models::ApiOperation>]
        def section_operations(section, incoming:)
          (section || {}).flat_map do |key, node|
            next [] unless node.is_a?(Hash)

            shared = Array(node[:parameters])
            node.slice(*HTTP_METHODS.map(&:to_sym)).flat_map do |verb, body|
              operation = build_operation(key.to_s, verb, body, shared, incoming: incoming)
              incoming ? [operation] : [operation, *callback_operations(body, operation)]
            end
          end
        end

        # callbacks операции OpenAPI 3.x — тот же провайдер зовёт адрес адаптера сам,
        # поэтому они тоже incoming; имя выражения callback используется как путь.
        # @param body [Hash] операция, у которой могут быть объявлены callbacks
        # @return [Array<Models::ApiOperation>]
        def callback_operations(body, origin)
          (body[:callbacks] || {}).flat_map do |name, expressions|
            expressions.flat_map do |_expression, node|
              next [] unless node.is_a?(Hash)

              shared = Array(node[:parameters])
              node.slice(*HTTP_METHODS.map(&:to_sym)).map do |verb, cb_body|
                build_operation(name.to_s, verb, cb_body, shared, incoming: true,
                                                                  callback_origin: origin)
              end
            end
          end
        end

        # @param path [String] шаблон пути или имя события webhook/callback
        # @param verb [Symbol] глагол HTTP
        # @param body [Hash] тело операции из описания
        # @param shared [Array<Hash>] параметры, объявленные на уровне пути
        # @param incoming [Boolean] операция объявлена в webhooks или callbacks
        # @return [Models::ApiOperation]
        def build_operation(path, verb, body, shared, incoming: false, callback_origin: nil)
          Models::ApiOperation.new(
            operation_id: body[:operationId] || (incoming ? path : nil),
            http_method: verb, path: path, incoming: incoming, callback_origin: callback_origin,
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
