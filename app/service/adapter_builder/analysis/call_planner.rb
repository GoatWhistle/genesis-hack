# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Параметры запроса к провайдеру: глагол, адрес, параметры, заголовки, тело.
      class CallPlanner
        # Один запрос к провайдеру целиком.
        Request = Struct.new(:http_method, :path, :path_arguments, :query, :headers, :payload,
                             :unfilled, keyword_init: true)

        Plan = Struct.new(:requests, :warnings, keyword_init: true)

        # @param rules [Ports::Rules] роли контракта, словари полей и параметров
        def initialize(rules)
          @rules = rules
        end

        # Запрос планируется для каждой роли с признаком calls_provider.
        # @param bindings [Hash{Symbol => Models::RoleBinding}] розданные роли
        # @return [Plan] запросы по ролям, которым нашлась операция
        def call(bindings)
          @warnings = []
          @create = bindings.values.find do |binding|
            binding.role.trait?(:creates_operation)
          end&.operation
          requests = @rules.roles_with(:calls_provider).to_h do |role|
            [role.name, request_for(bindings, role.name)]
          end
          Plan.new(requests: requests.compact, warnings: @warnings)
        end

        private

        # @param bindings [Hash{Symbol => Models::RoleBinding}]
        # @param role [Symbol]
        # @return [Request, nil] nil, если роль осталась заглушкой
        def request_for(bindings, role)
          operation = bindings[role]&.operation
          return nil if operation.nil?

          body = PayloadBuilder.new(@rules).call(operation: operation)
          @warnings.concat(body.warnings)
          @unfilled = []
          Request.new(http_method: operation.http_method, path: operation.path,
                      path_arguments: path_arguments(operation), query: query(operation),
                      headers: body.headers, payload: body.fields, unfilled: @unfilled)
        end

        # Параметры пути заполняются по словарю: payout_id узнаётся регуляркой.
        # @param operation [Models::ApiOperation]
        # @return [Hash{String => String}] имя параметра → выражение на Ruby
        def path_arguments(operation)
          operation.path.scan(/\{([^}]+)\}/).flatten.to_h do |name|
            parameter = operation.path_parameters.find do |item|
              item[:name] == name
            end || { name: name }
            [name, path_source(parameter, operation)]
          end
        end

        def path_source(parameter, operation)
          if ResourceParameters.identifier(@create, operation) == parameter[:name]
            return provider_identifier_source
          end

          fixed_source(parameter[:schema] || {}) || configured_source(parameter, operation)
        end

        def provider_identifier_source
          @rules.path_params.find do |entry|
            entry[:field].to_s == "provider_id"
          end&.dig(:source) || "nil"
        end

        def fixed_source(schema)
          return schema[:default].inspect if schema.key?(:default)

          schema[:enum].first.inspect if Array(schema[:enum]).one?
        end

        # Неизвестные параметры требуют явной настройки, включая ID родителя.
        def configured_source(parameter, operation)
          @warnings << "#{operation.method_name}: задайте параметр #{parameter[:name]} в реквизитах"
          entry = @rules.path_params.find { |item| item[:field].to_s == "configured_parameter" }
          return format(entry[:source], name: parameter[:name].inspect) if entry&.dig(:source)

          @unfilled << parameter[:name]
          "nil"
        end

        # Необязательные параметры запроса пропускаются.
        # @param operation [Models::ApiOperation]
        # @return [Hash{String => String}] имя параметра → выражение на Ruby
        def query(operation)
          required = operation.query_parameters.select { |parameter| parameter[:required] }
          required.to_h { |parameter| [parameter[:name], expression(parameter, operation)] }
        end

        # Незаполненный параметр уходит в предупреждения и в TODO рядом с запросом.
        # @param parameter [Hash] описание параметра
        # @param operation [Models::ApiOperation] источник имени операции для предупреждения
        # @return [String] выражение из словаря либо "nil"
        def expression(parameter, operation)
          entry = @rules.field_for(@rules.path_params, snake_case(parameter[:name]))
          return entry[:source] if entry&.dig(:source)

          @warnings << "#{operation.method_name}: правила не знают, чем заполнить " \
                       "параметр #{parameter[:name]}"
          @unfilled << parameter[:name]
          "nil"
        end

        # @param value [String]
        # @return [String] имя параметра в форме, принятой в словаре
        def snake_case(value)
          value.gsub(/([a-z\d])([A-Z])/, '\1_\2').tr("-", "_").downcase
        end
      end
    end
  end
end
