# frozen_string_literal: true

module Repositories
  module Rules
    # Хранилище правил: набор файлов по ключу вида contracts/<профиль>/contract.yml.
    module Store
      # @param _key [String]
      # @return [String] содержимое
      # @raise [ArgumentError] такого ключа нет
      def read(_key) = raise(NotImplementedError, "#{self.class}#read")

      # @param _key [String]
      # @param _content [String]
      # @return [void]
      def write(_key, _content) = raise(NotImplementedError, "#{self.class}#write")

      # @param _prefix [String] начало ключа
      # @return [Array<String>] ключи по возрастанию
      def list(_prefix = "") = raise(NotImplementedError, "#{self.class}#list")

      # @param _key [String]
      # @return [Boolean]
      def exist?(_key) = raise(NotImplementedError, "#{self.class}#exist?")

      # Проверка, что объект реализует порт хранилища правил.
      # @param candidate [Object]
      # @return [Object] тот же объект
      # @raise [ArgumentError] объект не отвечает на часть методов
      def self.assert!(candidate)
        missing = %i[read write list exist?].reject { |name| candidate.respond_to?(name) }
        return candidate if missing.empty?

        raise ArgumentError, "хранилище правил не отвечает на: #{missing.join(", ")}"
      end
    end

    # Ключ приходит снаружи, поэтому проверяется: «../../etc/passwd» выйдет за пределы хранилища.
    module Key
      ALLOWED = %r{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z}
      TRAVERSAL = %r{(\A|/)\.\.(/|\z)}

      module_function

      # @param key [String]
      # @return [String] тот же ключ
      # @raise [ArgumentError] ключ пуст, ведёт наружу или содержит лишнее
      def safe!(key)
        value = key.to_s
        raise ArgumentError, "пустой ключ" if value.empty?
        raise ArgumentError, "недопустимый ключ: #{value}" unless ALLOWED.match?(value)
        raise ArgumentError, "ключ ведёт за пределы хранилища: #{value}" if TRAVERSAL.match?(value)

        value
      end
    end
  end
end
