# frozen_string_literal: true

module Repositories
  module Rules
    # Правила в бакете: та же раскладка ключей, что и на диске, с префиксом.
    class S3
      include Store

      DEFAULT_PREFIX = "rules"

      # @param client [Adapter::S3::Client] чем ходим в хранилище
      # @param prefix [String] общий префикс ключей внутри бакета
      def initialize(client:, prefix: DEFAULT_PREFIX)
        @client = client
        @prefix = prefix.to_s.delete_suffix("/")
      end

      # @return [String] как хранилище называется в сообщениях и в отчёте
      def to_s = "s3://#{@client.bucket}/#{@prefix}"

      # @param key [String]
      # @return [String]
      # @raise [ArgumentError] объекта нет
      def read(key)
        content = @client.get(full(key))
        raise ArgumentError, "не найдено: #{key}" if content.nil?

        content.dup.force_encoding(Encoding::UTF_8)
      end

      # @param key [String]
      # @param content [String]
      # @return [void]
      def write(key, content) = @client.put(full(key), content)

      # Префикс задаётся внутри и может быть пустым, поэтому не проверяется.
      # @param prefix [String]
      # @return [Array<String>] ключи без общего префикса
      def list(prefix = "")
        @client.list("#{@prefix}/#{prefix}").map { |key| key.delete_prefix("#{@prefix}/") }
      end

      # @param key [String]
      # @return [Boolean]
      def exist?(key) = @client.exist?(full(key))

      private

      # @param key [String]
      # @return [String] ключ объекта в бакете
      def full(key) = "#{@prefix}/#{Key.safe!(key)}"
    end
  end
end
