# frozen_string_literal: true

require "pathname"

module Adapter
  module Upload
    # Результат в каталоге output/<provider>/.
    class File
      include Store

      DEFAULT_ROOT = "output"

      # @param root [String, Pathname] каталог, в котором создаются разделы провайдеров
      def initialize(root: ENV.fetch("RSOCKET_OUTPUT", DEFAULT_ROOT))
        @root = Pathname.new(root)
      end

      # @return [String] как хранилище называется в сообщениях
      def to_s = "каталог #{@root}"

      # @param provider [String]
      # @param files [Hash{String => String}]
      # @return [Array<String>] пути записанных файлов
      def store(provider, files)
        directory = @root.join(provider).tap(&:mkpath)
        files.map do |name, content|
          path = directory.join(name)
          path.dirname.mkpath
          path.write(content)
          path.to_s
        end
      end
    end
  end
end
