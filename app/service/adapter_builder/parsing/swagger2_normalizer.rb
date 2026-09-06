# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Parsing
      # Приведение описания Swagger 2.0 к форме, которую разбирает SpecParser: тело
      # запроса и ответы переносятся под content, авторизация и серверы — под ключи
      # OpenAPI 3. Ссылки #/definitions/... не переписываются: тот же раздел кладётся
      # в документ ещё и под старым именем, чтобы SchemaResolver разрешал их как есть.
      class Swagger2Normalizer
        HTTP_METHODS = %w[get post put patch delete].freeze
        DEFAULT_CONTENT_TYPE = :"application/json"

        # @param document [Hash] сырое описание Swagger 2.0, ключи символами
        def initialize(document)
          @document = document
          @resolver = SchemaResolver.new(document)
        end

        # @return [Hash] документ в форме OpenAPI 3 для SpecParser
        def call
          {
            info: @document[:info],
            servers: servers,
            security: @document[:security],
            definitions: @document[:definitions] || {},
            components: { schemas: @document[:definitions] || {},
                          securitySchemes: security_schemes },
            paths: paths
          }
        end

        private

        # Swagger 2.0 собирает адрес из схемы, хоста и базового пути раздельно.
        # @return [Array<Hash>]
        def servers
          host = @document[:host]
          return [] if host.to_s.empty?

          scheme = Array(@document[:schemes]).first || "https"
          [{ url: "#{scheme}://#{host}#{@document[:basePath]}" }]
        end

        # basic в Swagger 2.0 задаётся типом целиком; приводим к паре type/scheme
        # OpenAPI 3, которую понимает Models::ApiSpec::SecurityScheme.
        # @return [Hash]
        def security_schemes
          (@document[:securityDefinitions] || {}).transform_values do |body|
            next body unless body[:type] == "basic"

            body.merge(type: "http", scheme: "basic")
          end
        end

        # @return [Hash]
        def paths
          (@document[:paths] || {}).to_h { |path, node| [path, path_item(node)] }
        end

        # @param node [Hash] узел пути: параметры уровня пути плюс операции
        # @return [Hash]
        def path_item(node)
          return node unless node.is_a?(Hash)

          shared = Array(node[:parameters])
          node.except(:parameters).to_h do |key, value|
            [key, HTTP_METHODS.include?(key.to_s) ? operation(value, shared) : value]
          end
        end

        # Тело из in: body становится requestBody, остальные параметры остаются
        # как есть; ответы переносятся из responses.<код>.schema под content.
        # @param body [Hash] операция целиком
        # @return [Hash]
        def operation(body, shared = [])
          return body unless body.is_a?(Hash)

          content_type = preferred_type(body[:consumes] || @document[:consumes])
          others, request = split_parameters(parameters(body, shared), content_type)
          merged = body.merge(parameters: others,
                              responses: responses(body[:responses],
                                                   body[:produces] || @document[:produces]))
          request ? merged.merge(requestBody: request) : merged
        end

        # Разрешаем ссылки до преобразования. Операция перекрывает параметры
        # пути по паре in/name, как предписано Swagger 2.0.
        def parameters(body, shared)
          resolved = (shared + Array(body[:parameters])).filter_map do |parameter|
            @resolver.call(parameter)
          end
          resolved.reverse.uniq { |parameter| [parameter[:in], parameter[:name]] }.reverse
        end

        # @param parameters [Array<Hash>] параметры операции вперемешку
        # @param content_type [Symbol] тип содержимого тела запроса
        # @return [Array(Array<Hash>, Hash, nil)] обычные параметры и requestBody
        def split_parameters(parameters, content_type)
          body_param = parameters.find { |parameter| parameter[:in].to_s == "body" }
          others = parameters.reject { |parameter| parameter[:in].to_s == "body" }
                             .map { |parameter| with_schema(parameter) }
          [others, body_param && request_body(body_param, content_type)]
        end

        # Параметры не-body в Swagger 2.0 несут тип на верхнем уровне, а не в schema.
        # @param parameter [Hash]
        # @return [Hash]
        def with_schema(parameter)
          schema = parameter.slice(:type, :format, :enum, :items, :default)
          schema.empty? ? parameter : parameter.merge(schema: schema)
        end

        # @param parameter [Hash] параметр с in: body
        # @param content_type [Symbol]
        # @return [Hash] requestBody в форме OpenAPI 3
        def request_body(parameter, content_type)
          { description: parameter[:description], required: parameter[:required] == true,
            content: { content_type => { schema: parameter[:schema] } } }
        end

        # @param responses [Hash, nil] ответы операции
        # @param produces [Array<String>, nil]
        # @return [Hash]
        def responses(responses, produces)
          content_type = preferred_type(produces)
          (responses || {}).to_h do |code, body|
            [code, response_body(@resolver.call(body), content_type)]
          end
        end

        # @param body [Hash, nil] тело ответа
        # @param content_type [Symbol]
        # @return [Hash, nil]
        def response_body(body, content_type)
          return body unless body.is_a?(Hash)

          schema = body[:schema]
          normalized = body.except(:schema)
          schema ? normalized.merge(content: { content_type => { schema: schema } }) : normalized
        end

        # @param list [Array<String>, nil] consumes или produces
        # @return [Symbol]
        def preferred_type(list)
          Array(list).first&.to_sym || DEFAULT_CONTENT_TYPE
        end
      end
    end
  end
end
