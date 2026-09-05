# frozen_string_literal: true

require "json"
require "rack"

module Controller
  # HTTP поверх менеджера сборок. Слой тонкий: разобрать запрос, позвать сервис,
  # напечатать результат JSON-ом. Ни одного решения о содержимом здесь не
  # принимается — иначе HTTP и командная строка начали бы расходиться.
  module Http
    # Как читается запрос и как выглядит ответ. Вынесено из контроллера: это
    # работа с протоколом, а не с содержимым.
    module Payload
      CONTENT_TYPE = "application/json; charset=utf-8"
      MULTIPART = "multipart/form-data"

      # @param request [Rack::Request]
      # @return [String] содержимое из тела или из приложенного файла
      def content_of(request)
        return body_of(request) unless request.media_type == MULTIPART

        upload = request.params["file"]
        raise ArgumentError, "в форме нет поля file" unless upload.is_a?(Hash)

        upload.fetch(:tempfile).read.dup.force_encoding(Encoding::UTF_8)
      end

      # Тело читаем сами и берём параметры только из строки запроса. Иначе Rack,
      # увидев в Content-Type форму (а curl ставит её по умолчанию), разобрал бы
      # тело как форму и оставил нас без описания. Кодировку назначаем сами:
      # Rack отдаёт поток байтами, а описания приходят текстом в UTF-8.
      # @param request [Rack::Request]
      # @return [String]
      def body_of(request)
        request.body&.read.to_s.dup.force_encoding(Encoding::UTF_8)
      rescue StandardError
        ""
      end

      # @param value [String, nil]
      # @param name [String] имя параметра — для текста ошибки
      # @return [String]
      # @raise [ArgumentError] параметр не передали
      def present!(value, name)
        return value unless value.to_s.strip.empty?

        raise ArgumentError, "не передан обязательный параметр #{name}"
      end

      # @param status [Integer] код ответа
      # @param payload [Hash] тело ответа
      # @return [Array(Integer, Hash, Array<String>)] ответ Rack
      def json(status, payload)
        body = "#{JSON.pretty_generate(payload)}\n"
        [status,
         { "content-type" => CONTENT_TYPE, "content-length" => body.bytesize.to_s },
         [body]]
      end
    end

    class Api
      include Payload

      YAML_TYPE = "application/yaml; charset=utf-8"
      RULES = "/rules"

      ROUTES = {
        %w[GET /] => :index,
        %w[GET /health] => :health,
        %w[GET /openapi.yaml] => :openapi,
        %w[GET /contracts] => :contracts,
        %w[GET /rules] => :rules,
        %w[POST /build] => :build
      }.freeze

      # Ручки менеджера правил адресуют файл ключом, поэтому разбираются отдельно
      # от таблицы точных совпадений: GET/PUT /rules/<ключ>.
      KEY_METHODS = { "GET" => :read_rule, "PUT" => :write_rule, "POST" => :write_rule }.freeze

      # @param library [Service::BuildManager::Library] правила и шаблоны
      # @param assembler [Service::BuildManager::Assembler] чем собираем адаптеры
      def initialize(library:, assembler:)
        @library = library
        @assembler = assembler
      end

      # @param env [Hash] окружение Rack
      # @return [Array(Integer, Hash, Array<String>)] ответ Rack
      def call(env)
        request = Rack::Request.new(env)
        route(request)
      rescue ArgumentError => e
        json(400, error: e.message)
      rescue RuntimeError => e
        json(422, error: e.message)
      rescue StandardError => e
        json(500, error: "#{e.class}: #{e.message}")
      end

      private

      # @param request [Rack::Request]
      # @return [Array] ответ Rack
      def route(request)
        handler = ROUTES[[request.request_method, request.path_info]]
        return send(handler, request) if handler

        key = rule_key(request)
        handler = KEY_METHODS[request.request_method] if key
        return send(handler, request, key) if handler

        not_found(request)
      end

      # @param request [Rack::Request]
      # @return [String, nil] ключ файла правил из пути
      def rule_key(request)
        path = request.path_info
        return nil unless path.start_with?("#{RULES}/")

        Rack::Utils.unescape(path.delete_prefix("#{RULES}/"))
      end

      # Сам себе документация: по корню видно, что умеет сервис.
      # @return [Array] ответ Rack
      def index(_request)
        json(200, service: "rsocket", contract: Config::Catalog.default,
                  rules: @library.location, output: @assembler.destination,
                  endpoints: endpoints, openapi: "GET /openapi.yaml")
      end

      # @return [Array] ответ Rack
      def health(_request)
        json(200, status: "ok", rules: @library.location, contracts: @library.names)
      end

      # Сервис отдаёт собственное описание OpenAPI: тем же форматом, который он и
      # разбирает, — его можно открыть в Swagger UI или скормить кодогенератору.
      # @return [Array] ответ Rack
      def openapi(_request)
        [200, { "content-type" => YAML_TYPE }, [Rsocket::OPENAPI.read]]
      end

      # @return [Array] ответ Rack
      def contracts(_request)
        json(200, contracts: @library.profiles)
      end

      # @param request [Rack::Request]
      # @return [Array] ответ Rack
      def rules(request)
        prefix = Rack::Utils.parse_query(request.query_string)["prefix"].to_s
        json(200, location: @library.location, files: @library.entries(prefix))
      end

      # @param _request [Rack::Request]
      # @param key [String] ключ файла правил
      # @return [Array] ответ Rack
      def read_rule(_request, key)
        json(200, key: key, content: @library.read(key))
      end

      # Содержимое приходит либо телом запроса, либо файлом из формы: правила
      # одинаково удобно и писать руками, и заливать готовым файлом.
      # @param request [Rack::Request]
      # @param key [String] ключ файла правил
      # @return [Array] ответ Rack
      def write_rule(request, key)
        json(200, saved: @library.save(key, content_of(request)))
      end

      # Сборка целиком: описание приходит телом, имя провайдера и профиль —
      # параметрами строки запроса.
      # @param request [Rack::Request]
      # @return [Array] ответ Rack
      def build(request)
        spec = body_of(request)
        params = Rack::Utils.parse_query(request.query_string)
        provider = present!(params["provider"], "provider")
        contract = params["contract"] || Config::Catalog.default

        built(@assembler.call(spec: spec, provider: provider, contract: contract))
      end

      # @param outcome [Service::BuildManager::Assembler::Outcome]
      # @return [Array] ответ Rack: напечатанные файлы, куда они легли и разбор
      def built(outcome)
        json(200, provider: outcome.provider, contract: outcome.contract,
                  warnings: outcome.warnings, locations: outcome.locations,
                  files: outcome.files, report: outcome.report)
      end

      # @return [Array<String>] что умеет сервис
      def endpoints
        ROUTES.keys.map { |method, path| "#{method} #{path}" } +
          ["GET #{RULES}/<ключ>", "PUT #{RULES}/<ключ>"]
      end

      # @param request [Rack::Request]
      # @return [Array] ответ Rack
      def not_found(request)
        json(404, error: "нет такой ручки: #{request.request_method} #{request.path_info}",
                  endpoints: endpoints)
      end
    end
  end
end
