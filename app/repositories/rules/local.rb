# frozen_string_literal: true

require "pathname"

module Repositories
  module Rules
    # Правила на диске: каталог app/config/rules как есть. Это хранилище по умолчанию —
    # с ним инструмент работает, даже если ни одного внешнего сервиса рядом нет.
    class Local
      include Store

      ROOT = Pathname.new(__dir__).join("..", "..", "config", "rules").expand_path.freeze

      # @param root [String, Pathname] каталог с правилами
      def initialize(root: ENV.fetch("RSOCKET_RULES_ROOT", ROOT.to_s))
        @root = Pathname.new(root).expand_path
      end

      # @return [String] как хранилище называется в сообщениях и в отчёте
      def to_s = "локальный каталог #{@root}"

      # @param key [String]
      # @return [String]
      # @raise [ArgumentError] файла нет
      def read(key)
        path = path_for(key)
        raise ArgumentError, "не найдено: #{key}" unless path.file?

        path.read
      end

      # @param key [String]
      # @param content [String]
      # @return [void]
      def write(key, content)
        path = path_for(key)
        path.dirname.mkpath
        path.write(content)
      end

      # @param prefix [String]
      # @return [Array<String>]
      def list(prefix = "")
        return [] unless @root.directory?

        Pathname.glob(@root.join("**", "*")).select(&:file?)
                .map { |path| path.relative_path_from(@root).to_s }
                .select { |key| key.start_with?(prefix) }.sort
      end

      # @param key [String]
      # @return [Boolean]
      def exist?(key) = path_for(key).file?

      private

      # @param key [String]
      # @return [Pathname] путь внутри каталога правил
      def path_for(key) = @root.join(Key.safe!(key))
    end
  end
end
