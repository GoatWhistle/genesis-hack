# frozen_string_literal: true

module Rsocket
  module Spec
    class ResponseNormalizer
      def initialize(schema_normalizer)
        @schema_normalizer = schema_normalizer
      end

      def normalize(responses)
        (responses || {}).to_h do |code, response|
          normalized_code = response_code(code)
          [normalized_code, build_response(normalized_code, response)]
        end
      end

      private

      def build_response(code, response)
        media = @schema_normalizer.media(response)
        Rsocket::Ir::Response.new(
          code: code,
          description: response["description"],
          fields: @schema_normalizer.fields(media&.dig("schema")),
          examples: @schema_normalizer.examples(media),
          headers: headers(response["headers"])
        )
      end

      def headers(raw_headers)
        (raw_headers || {}).map do |name, header|
          @schema_normalizer.field(name, header_schema(header))
        end
      end

      def header_schema(header)
        schema = (header["schema"] || {}).dup
        schema["description"] ||= header["description"]
        schema["example"] = header["example"] if header.key?("example")
        schema
      end

      def response_code(code)
        code.to_s.match?(/\A\d+\z/) ? code.to_i : code.to_s
      end
    end
  end
end
