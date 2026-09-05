# frozen_string_literal: true

module Adapter
  # Куда уходит результат сборки. Сценарий печатает файлы в память и не знает,
  # лягут они в каталог рядом или в бакет: за это отвечает выбранный адаптер.
  module Upload
    module Store
      # @param _provider [String] имя провайдера — им называется раздел с результатом
      # @param _files [Hash{String => String}] имя файла → содержимое
      # @return [Array<String>] куда именно всё легло
      def store(_provider, _files) = raise(NotImplementedError, "#{self.class}#store")

      # Проверка, что объект действительно умеет складывать результат.
      # @param candidate [Object]
      # @return [Object] тот же объект
      # @raise [ArgumentError] объект не отвечает на store
      def self.assert!(candidate)
        return candidate if candidate.respond_to?(:store)

        raise ArgumentError, "хранилище результата не отвечает на: store"
      end
    end
  end
end
