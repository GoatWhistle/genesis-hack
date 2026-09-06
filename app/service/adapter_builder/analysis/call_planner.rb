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
          operation.path_parameters.to_h do |parameter|
            [parameter[:name], expression(parameter, operation)]
          end
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
