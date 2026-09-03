# frozen_string_literal: true

module Rsocket
  module Spec
    class ParameterNormalizer
      def initialize(schema_normalizer)
        @schema_normalizer = schema_normalizer
      end

      def grouped(path_item, operation)
        merged(path_item, operation).group_by { |parameter| parameter["in"] }
      end

      def normalize(parameters)
        Array(parameters).map do |parameter|
          @schema_normalizer.field(
            parameter["name"], parameter_schema(parameter),
            required: parameter.fetch("required", false)
          )
        end
      end

      private

      def merged(path_item, operation)
        parameters = Array(path_item["parameters"]) + Array(operation["parameters"])
        parameters.reverse.uniq { |item| [item["in"], item["name"]] }.reverse
      end

      def parameter_schema(parameter)
        schema = (parameter["schema"] || {}).dup
        schema["description"] ||= parameter["description"]
        schema["example"] = parameter["example"] if parameter.key?("example")
        schema
      end
    end
  end
end
