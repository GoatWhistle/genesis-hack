# frozen_string_literal: true

require_relative "../dictionaries"
require_relative "text"

module Rsocket
  module Classify
    # Поиск поля по смыслу, а не по точному имени.
    #
    # Сумма бывает amount, sum и value, получатель — recipient, payee и
    # destination. Признак «по форме запроса» перестал бы работать на втором же
    # провайдере, если бы искал точные имена, поэтому имена лежат в словаре, а
    # здесь только механизм поиска.
    class Meanings
      def self.default(dictionaries = Rsocket::Dictionaries.default)
        new(dictionaries.fields)
      end

      def initialize(dictionary)
        @dictionary = dictionary
      end

      # deep: false — только верхний уровень тела. Нужно там, где вложенность
      # меняет смысл: поле type внутри получателя — это не тип события.
      def find(fields, meaning, deep: true)
        words = @dictionary[meaning.to_s]
        return if words.nil? || words.empty?

        searched = deep ? flatten(fields) : Array(fields)
        searched.find { |field| named?(field, words) }
      end

      def any?(fields, meaning, deep: true)
        !find(fields, meaning, deep: deep).nil?
      end

      # Поля вместе со всей вложенностью: конверт data.state ничем не хуже
      # плоского status, и пропускать его нельзя.
      def flatten(fields)
        Array(fields).flat_map { |field| [field, *flatten(descendants(field))] }
      end

      private

      def descendants(field) = [*field.children, field.item].compact

      def named?(field, words)
        !Text.find(names(field), words).nil?
      end

      # Имя сверяем и по словам, и целиком: transferNo распадается на transfer
      # и no, но узнаётся именно как transfer_no.
      def names(field)
        tokens = Text.tokens(field.name)
        tokens + [tokens.join("_")]
      end
    end
  end
end
