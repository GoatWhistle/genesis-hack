# frozen_string_literal: true

require "yaml"
require "json"

module Adapter
  module Loader
    # Разбор текста описания API; источник задаёт адаптер.
    module Document
      MAX_BYTES = 8 * 1024 * 1024

      module_function

      # @param content [String] текст описания
      # @param json [Boolean] разбирать как JSON; иначе YAML, он же понимает JSON
      # @return [Object] разобранный документ, ещё не проверенный на тип
      # @raise [ArgumentError] текст не разобрался
      def parse(content, json: false)
        json ? parse_json(content) : parse_yaml(content)
      end

      # @param document [Object] разобранный документ
      # @param source [String] чем описание адресовалось — для текста ошибки
      # @return [Hash] тот же документ
      # @raise [ArgumentError] описание не объект
      def ensure_object(document, source)
        return document if document.is_a?(Hash)

        raise ArgumentError, "описание API не объект: #{source}"
      end

      # @param size [Integer] размер описания в байтах
      # @param source [String] чем описание адресовалось
      # @return [void]
      # @raise [ArgumentError] описание больше допустимого
      def ensure_size(size, source)
        return if size <= MAX_BYTES

        raise ArgumentError, "описание API слишком велико: #{source}"
      end

      # @param content [String]
      # @return [Object]
      # @raise [ArgumentError] YAML не разобрался
      def parse_yaml(content)
        YAML.safe_load(content, aliases: true, symbolize_names: true)
      rescue Psych::Exception => e
        raise ArgumentError, "не разобрать YAML: #{e.message}"
      end

      # @param content [String]
      # @return [Object]
      # @raise [ArgumentError] JSON не разобрался
      def parse_json(content)
        JSON.parse(content, symbolize_names: true)
      rescue JSON::ParserError => e
        raise ArgumentError, "не разобрать JSON: #{e.message}"
      end
    end
  end
end
