# frozen_string_literal: true

require "pathname"

module Adapter
  module Loader
    # Модуль перекрывает ::File: внутри только явные ::File и ::Pathname.
    module File
      # Чтение описания с диска: формат по расширению, иначе YAML (он же читает JSON).
      class SpecLoader
        include Service::AdapterBuilder::Ports::SpecSource

        JSON_EXTENSIONS = [".json"].freeze

        # @param reference [String, Pathname] путь к файлу описания
        # @return [Hash] документ OpenAPI, ключи символами
        # @raise [ArgumentError] файла нет, он слишком велик, не разобрался или не объект
        def read(reference)
          path = Pathname.new(reference.to_s).expand_path
          raise ArgumentError, "описание API не найдено: #{path}" unless path.file?

          Document.ensure_size(path.size, path)
          document = Document.parse(path.read, json: json?(path))
          Document.ensure_object(document, path)
        end

        private

        # @param path [Pathname]
        # @return [Boolean] расширение говорит, что это JSON
        def json?(path) = JSON_EXTENSIONS.include?(path.extname.downcase)
      end
    end
  end
end
