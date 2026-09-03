# frozen_string_literal: true

require_relative "../errors"
require_relative "../ir"
require_relative "coverage_notes"
require_relative "operation_normalizer"
require_relative "schema_normalizer"
require_relative "security_normalizer"

module Rsocket
  module Spec
    class Normalizer
      TEST_ENV_WORDS = %w[sandbox staging test testing].freeze
      PRODUCTION_ENV_WORDS = %w[production prod live].freeze

      def self.normalize(source)
        new(source).call
      end

      def initialize(source)
        @document = source.respond_to?(:document) ? source.document : source
        @raw_document = source.respond_to?(:raw_document) ? source.raw_document : @document
        @notes = source_notes(source)
      end

      def call
        security = SecurityNormalizer.new(@document, @notes)
        operations = OperationNormalizer.new(@document, SchemaNormalizer.new, security).operations
        ensure_operations(operations)
        security.note_undeclared_authentication(operations)
        CoverageNotes.new(operations, @notes).call
        build_spec(operations, security.schemes)
      end

      private

      def source_notes(source)
        notes = source.respond_to?(:notes) ? source.notes : []
        Array(notes).map { |note| normalize_note(note) }
      end

      def normalize_note(note)
        return note if note.is_a?(Rsocket::Ir::Note)

        Rsocket::Ir::Note.new(level: note.level, where: note.where, message: note.message)
      end

      def ensure_operations(operations)
        return unless operations.empty?

        raise Rsocket::SpecError.new(
          "описание не содержит ни одной HTTP-операции", where: "paths"
        )
      end

      def build_spec(operations, security_schemes)
        Rsocket::Ir::Spec.new(
          title: @document.dig("info", "title"), version: @document.dig("info", "version"),
          description: @document.dig("info", "description"), servers: servers,
          security_schemes: security_schemes, operations: operations,
          raw_schemas: @raw_document.dig("components", "schemas") || {}, notes: @notes
        )
      end

      def servers
        Array(@document["servers"]).map do |server|
          Rsocket::Ir::Server.new(
            url: server["url"], description: server["description"], env: environment(server)
          )
        end
      end

      def environment(server)
        text = [server["url"], server["description"]].compact.join(" ").downcase
        return :sandbox if TEST_ENV_WORDS.any? { |word| text.match?(/\b#{word}\b/) }
        return :production if PRODUCTION_ENV_WORDS.any? { |word| text.match?(/\b#{word}\b/) }

        :unknown
      end
    end
  end
end
