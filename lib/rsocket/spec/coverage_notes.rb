# frozen_string_literal: true

require_relative "../ir"

module Rsocket
  module Spec
    # Пробелы описания, из-за которых заготовка выйдет беднее.
    #
    # Ни примеры, ни ответы с ошибками OpenAPI не требует, и падать тут не за
    # что. Но именно на этих местах сгенерированный код придётся дописывать
    # руками, поэтому мы называем их заранее, а не оставляем на потом.
    class CoverageNotes
      def initialize(operations, notes)
        @operations = operations
        @notes = notes
      end

      def call
        @operations.each do |operation|
          add_missing_examples(operation) unless examples?(operation)
          add_missing_errors(operation) unless error_response?(operation)
        end
      end

      private

      def examples?(operation)
        operation.request_examples.any? || fields_have_examples?(operation.request_fields) ||
          operation.responses.values.any? { |response| response_has_examples?(response) }
      end

      def response_has_examples?(response)
        response.examples.any? || fields_have_examples?(response.fields)
      end

      def fields_have_examples?(fields)
        fields.any? do |field|
          !field.example.nil? || fields_have_examples?(field.children) ||
            (field.item && fields_have_examples?([field.item]))
        end
      end

      def error_response?(operation)
        operation.responses.keys.any? do |code|
          code.is_a?(Integer) ? code >= 400 : code.to_s.match?(/\A[45]/)
        end
      end

      def add_missing_examples(operation)
        add_note(
          operation, "responses",
          "Для операции не описано ни одного примера; мок соберёт ответ по схеме"
        )
      end

      def add_missing_errors(operation)
        add_note(
          operation, "responses",
          "Для операции не описаны ответы с ошибками; обработку отказов нужно проверить вручную"
        )
      end

      def add_note(operation, section, message)
        @notes << Rsocket::Ir::Note.new(
          level: :needs_confirmation,
          where: "paths.#{operation.path}.#{operation.http_method}.#{section}",
          message: message
        )
      end
    end
  end
end
