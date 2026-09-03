# frozen_string_literal: true

require_relative "../ir"

module Rsocket
  module Spec
    class SchemaNormalizer
      ATTRIBUTES = {
        type: "type", format: "format", description: "description", enum: "enum",
        pattern: "pattern", minimum: "minimum", maximum: "maximum",
        max_length: "maxLength", example: "example"
      }.freeze

      def fields(schema)
        return [] unless schema.is_a?(Hash)

        required = Array(schema["required"])
        (schema["properties"] || {}).map do |name, property|
          field(name, property, required: required.include?(name))
        end
      end

      def field(name, schema, required: false, parent_path: nil, path: nil)
        schema ||= {}
        path ||= [parent_path, name].compact.join(".")
        Rsocket::Ir::Field.new(
          **field_attributes(schema), name: name, required: required, path: path,
                                      children: child_fields(schema, path),
                                      item: array_item(schema["items"], path)
        )
      end

      def media(container)
        content = container&.dig("content")
        return unless content.is_a?(Hash) && !content.empty?

        content["application/json"] || json_suffix_media(content) || content.values.first
      end

      def examples(media)
        return {} unless media.is_a?(Hash)

        values = (media["examples"] || {}).to_h do |name, example|
          [name, example_value(example)]
        end
        singular = singular_example(media)
        values["default"] = singular.last if singular.first
        values
      end

      private

      def field_attributes(schema)
        ATTRIBUTES.to_h { |attribute, key| [attribute, schema[key]] }
      end

      def child_fields(schema, path)
        required = Array(schema["required"])
        (schema["properties"] || {}).map do |name, child|
          field(name, child, required: required.include?(name), parent_path: path)
        end
      end

      def array_item(schema, path)
        field("item", schema, path: "#{path}[]") if schema.is_a?(Hash)
      end

      def json_suffix_media(content)
        content.find { |type, _media| type.end_with?("+json") }&.last
      end

      def example_value(example)
        return example["value"] if example.is_a?(Hash) && example.key?("value")

        example
      end

      def singular_example(media)
        return [true, media["example"]] if media.key?("example")

        schema = media["schema"]
        return [true, schema["example"]] if schema.is_a?(Hash) && schema.key?("example")

        [false, nil]
      end
    end
  end
end
