# frozen_string_literal: true

require_relative "parameter_normalizer"
require_relative "response_normalizer"

module Rsocket
  module Spec
    class OperationNormalizer
      HTTP_METHODS = %w[get post put patch delete].freeze

      def initialize(document, schema_normalizer, security_normalizer)
        @document = document
        @schema = schema_normalizer
        @security = security_normalizer
        @parameters = ParameterNormalizer.new(schema_normalizer)
        @responses = ResponseNormalizer.new(schema_normalizer)
      end

      def operations
        (@document["paths"] || {}).flat_map do |path, path_item|
          operations_for_path(path, path_item)
        end
      end

      private

      def operations_for_path(path, path_item)
        return [] unless path_item.is_a?(Hash)

        HTTP_METHODS.filter_map do |method|
          operation = path_item[method]
          build(path, method, path_item, operation) if operation.is_a?(Hash)
        end
      end

      def build(path, method, path_item, operation)
        grouped = @parameters.grouped(path_item, operation)
        media = @schema.media(operation["requestBody"])
        Rsocket::Ir::Operation.new(
          **identity(path, method, operation), **parameters(grouped),
          request_fields: @schema.fields(media&.dig("schema")),
          request_examples: @schema.examples(media),
          responses: @responses.normalize(operation["responses"]),
          security: effective_security(operation)
        )
      end

      def identity(path, method, operation)
        {
          http_method: method.to_sym, path: path, operation_id: operation["operationId"],
          tags: Array(operation["tags"]), summary: operation["summary"],
          description: operation["description"]
        }
      end

      def parameters(grouped)
        {
          path_params: @parameters.normalize(grouped["path"]),
          query_params: @parameters.normalize(grouped["query"]),
          header_params: @parameters.normalize(grouped["header"])
        }
      end

      def effective_security(operation)
        raw = operation.key?("security") ? operation["security"] : @document["security"]
        @security.names(raw)
      end
    end
  end
end
