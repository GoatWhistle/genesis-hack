# frozen_string_literal: true

require "cgi"
require "net/http"
require "uri"

module Adapter
  # Минимальный клиент S3 на стандартной библиотеке: четыре операции, которые нам
  # нужны, и подпись AWS Signature Version 4. Готового SDK не берём намеренно —
  # он тянет за собой десятки гемов ради GET, PUT, HEAD и списка объектов.
  #
  # Адресация путевая (endpoint/bucket/key), поэтому клиент одинаково работает и с
  # настоящим S3, и с MinIO, и с любым совместимым хранилищем.
  module S3
    class Client
      CONTENT_TYPE = "application/octet-stream"

      # Хранилище ответило не тем, чего мы ждали.
      class Error < StandardError; end

      # @param endpoint [String] адрес хранилища, например http://minio:9000
      # @param bucket [String] имя бакета
      # @param access_key_id [String]
      # @param secret_access_key [String]
      # @param region [String] регион подписи; для MinIO подойдёт любой
      # @param open_timeout [Integer]
      # @param read_timeout [Integer]
      def initialize(endpoint:, bucket:, access_key_id:, secret_access_key:,
                     region: "us-east-1", open_timeout: 5, read_timeout: 15)
        @endpoint = URI.parse(endpoint)
        @bucket = bucket
        @access_key_id = access_key_id
        @secret_access_key = secret_access_key
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @signature = Signature.new(access_key_id: access_key_id, region: region,
                                   secret_access_key: secret_access_key)
      end

      attr_reader :bucket, :endpoint

      # @param key [String]
      # @return [String, nil] содержимое объекта; nil, если его нет
      # @raise [Error] хранилище ответило ошибкой
      def get(key)
        response = send_request(Net::HTTP::Get, path_for(key))
        return nil if response.code == "404"

        body_of(response, "GET #{key}")
      end

      # @param key [String]
      # @param content [String]
      # @return [void]
      # @raise [Error] хранилище ответило ошибкой
      def put(key, content)
        body = content.to_s.dup.force_encoding(Encoding::BINARY)
        response = send_request(Net::HTTP::Put, path_for(key), body: body)
        body_of(response, "PUT #{key}")
      end

      # @param key [String]
      # @return [Boolean]
      def exist?(key)
        send_request(Net::HTTP::Head, path_for(key)).code.start_with?("2")
      end

      # Список ключей целиком: хранилище отдаёт его страницами, и без склейки
      # правила из большого бакета выглядели бы наполовину пропавшими.
      # @param prefix [String]
      # @return [Array<String>] ключи по возрастанию
      def list(prefix = "")
        keys = []
        token = nil
        loop do
          page = list_page(prefix, token)
          keys.concat(page.fetch(:keys))
          token = page.fetch(:token)
          break if token.nil?
        end
        keys.sort
      end

      # @return [Boolean] отвечает ли хранилище и виден ли бакет
      def available?
        send_request(Net::HTTP::Head, "/#{@bucket}").code.start_with?("2", "3")
      rescue StandardError
        false
      end

      # @return [void] создаёт бакет, если его ещё нет
      def ensure_bucket
        return if available?

        body_of(send_request(Net::HTTP::Put, "/#{@bucket}", body: ""), "PUT #{@bucket}")
      end

      private

      # @param prefix [String]
      # @param token [String, nil] маркер следующей страницы
      # @return [Hash] { keys:, token: }
      def list_page(prefix, token)
        query = { "list-type" => "2", "prefix" => prefix }
        query["continuation-token"] = token if token
        xml = body_of(send_request(Net::HTTP::Get, "/#{@bucket}", query: query), "LIST #{prefix}")
        { keys: xml.scan(%r{<Key>(.*?)</Key>}m).flatten.map { |key| unescape(key) },
          token: xml[%r{<NextContinuationToken>(.*?)</NextContinuationToken>}m, 1] }
      end

      # @param key [String]
      # @return [String] путь запроса
      def path_for(key) = "/#{@bucket}/#{escape(key)}"

      # @param type [Class] класс запроса Net::HTTP
      # @param path [String]
      # @param query [Hash]
      # @param body [String, nil]
      # @return [Net::HTTPResponse]
      def send_request(type, path, query: {}, body: nil)
        request = build(type, path, query, body)
        Net::HTTP.start(@endpoint.host, @endpoint.port, use_ssl: @endpoint.scheme == "https",
                                                        open_timeout: @open_timeout,
                                                        read_timeout: @read_timeout) do |http|
          http.request(request)
        end
      end

      # @return [Net::HTTPRequest] запрос с подписью
      def build(type, path, query, body)
        uri = uri_for(path, query)
        request = type.new(uri)
        request["content-type"] = CONTENT_TYPE if body
        request.body = body if body
        @signature.sign(request, host: host_of(uri), path: path,
                                 query: uri.query.to_s, payload: body)
        request
      end

      # @param uri [URI]
      # @return [String] хост с портом: он попадает и в подпись, и в заголовок Host
      def host_of(uri)
        default = uri.scheme == "https" ? 443 : 80
        uri.port == default ? uri.host : "#{uri.host}:#{uri.port}"
      end

      # @return [URI] полный адрес запроса
      def uri_for(path, query)
        uri = @endpoint.dup
        uri.path = path
        uri.query = canonical_query(query) unless query.empty?
        uri
      end

      # @param response [Net::HTTPResponse]
      # @param what [String] что делали — для текста ошибки
      # @return [String] тело ответа
      # @raise [Error] код ответа не из двухсотых
      def body_of(response, what)
        return response.body.to_s if response.code.start_with?("2")

        raise Error, "S3 ответил #{response.code} на #{what}: #{response.body.to_s[0, 300]}"
      end

      # @return [String] символы, которые в ключе не экранируются
      def escape(key) = key.split("/").map { |part| CGI.escape(part).gsub("+", "%20") }.join("/")

      # @return [String]
      def unescape(value) = value.gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">")

      # @param query [Hash]
      # @return [String] параметры в порядке, которого требует подпись
      def canonical_query(query)
        query.sort.map { |name, value| "#{CGI.escape(name)}=#{CGI.escape(value.to_s)}" }.join("&")
      end
    end
  end
end
