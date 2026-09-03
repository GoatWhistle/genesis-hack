# frozen_string_literal: true

module Rsocket
  module Classify
    # Разбор имён на слова и сверка со словарём.
    #
    # Имена в описаниях слитные и разноязычные: createPayout, transfer_no,
    # /v1/transfers/{transferNo}, «Создать выплату». Прежде чем что-то искать в
    # словаре, всё это надо привести к одному виду — списку слов в нижнем
    # регистре.
    module Text
      # Слово от четырёх букв ищется по вхождению: так одна основа «status»
      # покрывает и statuses, и statusCode, а «созда» — и «создать», и
      # «создание». Короткие слова сравниваются целиком, иначе «new» найдётся
      # внутри «renewal», а «id» — внутри «invalid».
      SUBSTRING_MIN = 4

      module_function

      # Слова из произвольного набора строк: имя операции, адрес, описание.
      def tokens(*sources)
        sources.flatten.compact.flat_map { |source| split(source.to_s) }.uniq
      end

      def split(text)
        text
          .gsub(/([[:lower:]\d])([[:upper:]])/, '\1 \2')
          .downcase
          .split(/[^[:alnum:]]+/)
          .reject(&:empty?)
      end

      # Первое слово словаря, найденное среди слов имени. Возвращаем именно
      # слово, а не «да/нет»: его показываем человеку в формулировке признака.
      def find(tokens, words)
        Array(words).find { |word| tokens.any? { |token| matches?(token, word) } }
      end

      def matches?(token, word)
        return token == word if word.length < SUBSTRING_MIN

        token.include?(word)
      end
    end
  end
end
