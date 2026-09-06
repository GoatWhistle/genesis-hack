# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Поля ответов выбираются по собственной схеме роли и параметру её ресурса.
      class ResponseFields
        def initialize(rules, bindings)
          @rules = rules
          @bindings = bindings
        end

        # Путь к идентификатору операции в ответе на создание; не нашли — берём id.
        # @return [Array<String>] путь до поля
        def created_id_field
          created_identifier&.path || ["id"]
        end

        def created_identifier
          schema = create_operation&.success_response&.dig(:schema)
          probe = Parsing::SchemaProbe.new(schema)
          names = resource_id_names
          exact = probe.find(names.map { |name| /\A#{Regexp.escape(name)}\z/i }) unless names.empty?
          patterns = @rules.callback_fields.fetch(:operation_id)
          exact || probe.find(patterns)
        end

        def resource_id_names
          create = create_operation
          @bindings.values.filter_map do |binding|
            ResourceParameters.identifier(create, binding.operation)
          end.uniq
        end

        def created_id_header
          response = create_operation&.success_response
          return nil if created_identifier

          (response&.dig(:headers) || {}).keys.find { |name| name.to_s.casecmp?("location") }&.to_s
        end

        def status_fields
          patterns = @rules.callback_fields.fetch(:status)
          @bindings.transform_values do |binding|
            schema = binding.operation&.success_response&.dig(:schema)
            Parsing::SchemaProbe.new(schema).find(patterns)&.path || ["status"]
          end
        end

        private

        def create_operation
          @bindings.values.find { |binding| binding.role.trait?(:creates_operation) }&.operation
        end
      end
    end
  end
end
