# frozen_string_literal: true

require "openssl"
require "time"

module Adapter
  module S3
    # Подпись AWS Signature Version 4: порядок заголовков и параметров значим.
    class Signature
      ALGORITHM = "AWS4-HMAC-SHA256"
      TERMINATOR = "aws4_request"
      SIGNED_HEADERS = %w[host x-amz-content-sha256 x-amz-date].freeze

      # @param access_key_id [String]
      # @param secret_access_key [String]
      # @param region [String]
      # @param service [String]
      def initialize(access_key_id:, secret_access_key:, region:, service: "s3")
        @access_key_id = access_key_id
        @secret_access_key = secret_access_key
        @region = region
        @service = service
      end

      # Добавляет к запросу заголовки подписи.
      # @param request [Net::HTTPRequest] запрос, который уйдёт как есть
      # @param host [String] хост с портом — он же в заголовке Host
      # @param path [String] путь ровно в том виде, в каком он отправляется
      # @param query [String] параметры строки запроса в каноническом порядке
      # @param payload [String, nil] тело
      # @param now [Time] момент подписи
      # @return [void]
      def sign(request, host:, path:, query: "", payload: nil, now: Time.now.utc)
        stamp = now.strftime("%Y%m%dT%H%M%SZ")
        digest = OpenSSL::Digest::SHA256.hexdigest(payload.to_s)
        headers = { "host" => host, "x-amz-content-sha256" => digest, "x-amz-date" => stamp }
        headers.each { |name, value| request[name] = value }

        canonical = canonical_request(request.method, path, query, headers, digest)
        request["authorization"] = authorization(canonical, stamp)
      end

      private

      # @return [String] каноническая форма запроса
      def canonical_request(method, path, query, headers, digest)
        [method, path, query,
         "#{SIGNED_HEADERS.map { |name| "#{name}:#{headers.fetch(name)}" }.join("\n")}\n",
         SIGNED_HEADERS.join(";"), digest].join("\n")
      end

      # @param canonical [String] каноническая форма запроса
      # @param stamp [String] момент подписи
      # @return [String] значение заголовка Authorization
      def authorization(canonical, stamp)
        date = stamp[0, 8]
        scope = "#{date}/#{@region}/#{@service}/#{TERMINATOR}"
        signature = hmac(signing_key(date), string_to_sign(canonical, stamp, scope)).unpack1("H*")

        "#{ALGORITHM} Credential=#{@access_key_id}/#{scope}, " \
          "SignedHeaders=#{SIGNED_HEADERS.join(";")}, Signature=#{signature}"
      end

      # @return [String] строка, которую в итоге и подписываем
      def string_to_sign(canonical, stamp, scope)
        [ALGORITHM, stamp, scope, OpenSSL::Digest::SHA256.hexdigest(canonical)].join("\n")
      end

      # Ключ подписи: секрет → дата → регион → сервис.
      # @param date [String] ГГГГММДД
      # @return [String]
      def signing_key(date)
        key = hmac("AWS4#{@secret_access_key}", date)
        key = hmac(key, @region)
        key = hmac(key, @service)
        hmac(key, TERMINATOR)
      end

      # @return [String] сырой HMAC-SHA256
      def hmac(key, data) = OpenSSL::HMAC.digest("sha256", key, data)
    end
  end
end
