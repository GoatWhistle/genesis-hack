# frozen_string_literal: true

require "faraday"
require "json"
require "openssl"
require "rackup"
require "webrick"

require_relative "responder"

module Rsocket
  module Mock
    class DeliveryError < Rsocket::Error
      attr_reader :response

      def initialize(response)
        @response = response
        super("Приёмник вебхука ответил HTTP #{response.status}")
      end
    end

    # Поддельный сервер провайдера: обычное Rack-приложение, у которого нет
    # своей логики — весь ответ целиком берётся из описания API.
    #
    # Отдельно умеет постучаться вебхуком по нашему же адресу и подписать тело
    # HMAC. Это единственный способ проверить приём уведомлений до того, как
    # настоящий провайдер выдаст доступ к песочнице.
    class Server
      DEFAULT_SIGNATURE_HEADER = "X-Webhook-Signature"

      def initialize(spec)
        @responder = Responder.new(spec)
      end

      def call(environment)
        response = @responder.call(
          method: environment.fetch("REQUEST_METHOD"),
          path: environment.fetch("PATH_INFO")
        )
        render_response(response)
      rescue ExampleGenerationError => e
        render_response(generation_error(e))
      end

      def start(port: 4010, host: "127.0.0.1")
        Rackup::Server.start(
          app: self, server: "webrick", Host: host, Port: port,
          AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
        )
      end

      def deliver_webhook(
        url:, payload:, secret:, signature_header: DEFAULT_SIGNATURE_HEADER,
        invalid_signature: false
      )
        body = payload.is_a?(String) ? payload : JSON.generate(payload)
        signature = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
        signature = corrupt(signature) if invalid_signature
        response = Faraday.post(
          url, body, "Content-Type" => "application/json", signature_header => signature
        )
        raise DeliveryError, response unless response.success?

        response
      end

      private

      def render_response(response)
        body = JSON.generate(response.body)
        headers = response.headers.merge("content-type" => "application/json; charset=utf-8")
        [response.status, headers, [body]]
      end

      def generation_error(error)
        Response.new(
          status: 500,
          headers: {},
          body: { "error" => { "code" => "example_generation_failed", "message" => error.message } }
        )
      end

      def corrupt(signature)
        replacement = signature.start_with?("0") ? "1" : "0"
        replacement + signature[1..]
      end
    end
  end
end
