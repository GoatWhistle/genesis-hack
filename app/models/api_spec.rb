# frozen_string_literal: true

module Models
  # Описание API целиком: то, что нужно и классификатору, и шаблону.
  class ApiSpec
    Server = Struct.new(:url, :description, keyword_init: true)
    SecurityScheme = Struct.new(:name, :type, :location, :parameter, :scheme, keyword_init: true) do
      # Чем сервис подписывает запрос по этой схеме.
      # @return [Symbol] :api_key, :basic, :bearer или :unsupported
      def credential_kind
        return :api_key if type == "apiKey"
        return :basic if type == "http" && scheme == "basic"
        return :bearer if type == "http" && scheme == "bearer"

        :unsupported
      end
    end

    attr_reader :title, :description, :version, :servers, :security_schemes, :operations, :schemas

    # @param title [String] название API
    # @param version [String] версия API
    # @param servers [Array<Server>] серверы из описания, первый считается основным
    # @param security_schemes [Array<SecurityScheme>] объявленные схемы авторизации
    # @param operations [Array<Models::ApiOperation>] все операции описания
    # @param schemas [Hash{Symbol => Hash}] components/schemas как есть
    # @param description [String, nil] описание API
    def initialize(title:, version:, servers:, security_schemes:, operations:, schemas: {},
                   description: nil)
      @title = title
      @description = description
      @version = version
      @servers = servers
      @security_schemes = security_schemes
      @operations = operations
      @schemas = schemas
    end

    # Адрес провайдера по умолчанию — уходит в ENV.fetch сгенерированного класса.
    # @return [String, nil]
    def base_url
      servers.first&.url
    end

    # Название и описание одной строкой: в них провайдер называет лимиты словами.
    # @return [String]
    def text
      [title, description].compact.join("\n")
    end
  end
end
