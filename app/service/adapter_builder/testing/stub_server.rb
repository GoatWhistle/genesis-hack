# frozen_string_literal: true

require "json"
require "webrick"

module Service
  module AdapterBuilder
    module Testing
      # Подставной провайдер: отвечает примерами из fixtures.json, код задаёт answer.
      class StubServer
        # Полученный запрос.
        Received = Struct.new(:http_method, :path, :query, :headers, :body, keyword_init: true)
        # Адрес роли: шаблон для отчёта, регулярка для сопоставления.
        Route = Struct.new(:role, :http_method, :path, :pattern, keyword_init: true)

        HOST = "127.0.0.1"
        JSON_TYPE = "application/json"
        # На месте параметра пути допустимо любое значение без разделителя.
        PARAMETER = /\{[^}]+\}/

        # @param blueprint [Models::Blueprint] запланированные запросы и фикстуры
        def initialize(blueprint)
          @routes = routes(blueprint.calls)
          @cases = blueprint.fixtures.calls
          @answers = {}
          @received = []
          @lock = Mutex.new
        end

        # @return [StubServer] тот же объект после запуска приёма запросов
        def start
          @server = WEBrick::HTTPServer.new(BindAddress: HOST, Port: 0, AccessLog: [],
                                            Logger: WEBrick::Log.new(File::NULL))
          @server.mount_proc("/") { |request, response| handle(request, response) }
          @thread = Thread.new { @server.start }
          self
        end

        # @return [String] адрес, подставляемый собранному классу вместо адреса провайдера
        def url = "http://#{HOST}:#{@server.config[:Port]}"

        # @return [void]
        def stop
          @server&.shutdown
          @thread&.join(1)
        end

        # Код ответа на следующий запрос роли; прошлые запросы забываются.
        # @param role [Symbol] роль контракта
        # @param code [Integer, String] код ответа
        # @return [void]
        def answer(role, code)
          @answers[role] = code.to_i
          @lock.synchronize { @received.clear }
        end

        # @return [Received, nil] последний полученный запрос
        def last = @lock.synchronize { @received.last }

        # @param role [Symbol]
        # @return [Route, nil] адрес роли
        def route_for(role) = @routes.find { |route| route.role == role }

        # @param role [Symbol]
        # @return [Integer] наименьший описанный код 2xx; при отсутствии таких — 200
        def success_code(role)
          codes(role).grep(200..299).min || 200
        end

        # @param role [Symbol]
        # @return [Array<Integer>] коды отказов, описанные провайдером
        def error_codes(role) = codes(role).select { |code| code >= 400 }

        private

        # @param role [Symbol]
        # @return [Array<Integer>] коды ответов, описанные у этой роли
        def codes(role)
          @cases[role]&.responses.to_h.keys.map(&:to_i).sort
        end

        # @param calls [Hash{Symbol => Analysis::CallPlanner::Request}]
        # @return [Array<Route>]
        def routes(calls)
          calls.map do |role, call|
            Route.new(role: role, http_method: call.http_method.to_s.upcase,
                      path: call.path, pattern: pattern(call.path))
          end
        end

        # Предел -1 у split обязателен: иначе параметр в конце адреса теряется.
        # @param path [String] шаблон адреса провайдера
        # @return [Regexp] адрес с параметрами, подставленными кем угодно
        def pattern(path)
          /\A#{path.split(PARAMETER, -1).map { |part| Regexp.escape(part) }.join("[^/]+")}\z/
        end

        # @param request [WEBrick::HTTPRequest]
        # @param response [WEBrick::HTTPResponse]
        # @return [void]
        def handle(request, response)
          record(request)
          route = match(request)
          return miss(response, request) if route.nil?

          code = @answers.fetch(route.role, success_code(route.role))
          reply(response, code, @cases[route.role]&.responses&.dig(code.to_s) || {})
        end

        # @param request [WEBrick::HTTPRequest]
        # @return [Route, nil]
        def match(request)
          @routes.find do |route|
            route.http_method == request.request_method && route.pattern.match?(request.path)
          end
        end

        # @param request [WEBrick::HTTPRequest]
        # @return [void]
        def record(request)
          received = Received.new(http_method: request.request_method, path: request.path,
                                  query: request.query_string.to_s, headers: headers(request),
                                  body: body(request))
          @lock.synchronize { @received << received }
        end

        # @param request [WEBrick::HTTPRequest]
        # @return [Hash{String => String}] заголовки запроса, имена в нижнем регистре
        def headers(request)
          request.header.transform_values { |values| Array(values).first.to_s }
        end

        # @param request [WEBrick::HTTPRequest]
        # @return [String] тело запроса без обработки
        def body(request)
          request.body.to_s
        rescue StandardError
          ""
        end

        # Неизвестный адрес — промах собранного класса, а не отказ провайдера.
        # @param response [WEBrick::HTTPResponse]
        # @param request [WEBrick::HTTPRequest]
        # @return [void]
        def miss(response, request)
          reply(response, 404,
                "error" => "подставной провайдер не ждал #{request.request_method} #{request.path}")
        end

        # @param response [WEBrick::HTTPResponse]
        # @param code [Integer]
        # @param body [Hash]
        # @return [void]
        def reply(response, code, body)
          response.status = code
          response["Content-Type"] = JSON_TYPE
          response.body = JSON.generate(body)
        end
      end
    end
  end
end
