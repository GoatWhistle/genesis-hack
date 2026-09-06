# frozen_string_literal: true

module Adapter
  module Upload
    # Результат в бакете: <prefix>/<provider>/<файл>.
    class S3
      include Store

      DEFAULT_PREFIX = "output"

      # @param client [Adapter::S3::Client]
      # @param prefix [String] общий префикс ключей внутри бакета
      def initialize(client:, prefix: DEFAULT_PREFIX)
        @client = client
        @prefix = prefix.to_s.delete_suffix("/")
      end

      # @return [String] как хранилище называется в сообщениях
      def to_s = "s3://#{@client.bucket}/#{@prefix}"

      # @param provider [String]
      # @param files [Hash{String => String}]
      # @return [Array<String>] адреса объектов
      def store(provider, files)
        files.map do |name, content|
          key = "#{@prefix}/#{provider}/#{name}"
          @client.put(key, content)
          "s3://#{@client.bucket}/#{key}"
        end
      end
    end
  end
end
