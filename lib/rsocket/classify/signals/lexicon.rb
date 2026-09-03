# frozen_string_literal: true

require_relative "../evidence"
require_relative "../text"

module Rsocket
  module Classify
    module Signals
      # Признак «по словам»: сверка имени операции, адреса, тегов и описания со
      # словарём синонимов.
      #
      # Самый очевидный признак и самый ненадёжный: он работает ровно настолько,
      # насколько провайдер называл вещи своими именами. На описании, где
      # операции зовутся makeTransfer и transferInfo, он честно даёт мало — и это
      # правильное поведение, а не недоработка. Недостачу добирают признаки по
      # форме запроса и по связям через идентификаторы.
      class Lexicon
        SIGNAL = :lexicon

        # Что смотрим и какими словами это называть человеку в отчёте.
        Source = Data.define(:key, :tokens, :label)

        def initialize(context)
          @weights = context.dictionaries.weights["lexicon"] || {}
        end

        def evidence(operation, role)
          sources(operation).flat_map { |source| matches(source, role) }
        end

        private

        def sources(operation)
          [
            source(:operation_id, [operation.operation_id],
                   "имя операции «#{operation.operation_id}»"),
            source(:path, [operation.path], "адрес «#{operation.path}»"),
            source(:text, [operation.summary, operation.description], "описание операции"),
            source(:tag, operation.tags, "раздел «#{operation.tags.join(", ")}»")
          ].compact
        end

        def source(key, values, label)
          tokens = Text.tokens(values)
          Source.new(key: key, tokens: tokens, label: label) unless tokens.empty?
        end

        def matches(source, role)
          word_sets(source, role).filter_map { |kind, words| entry(source, kind, words) }
        end

        # У тега свой список слов: тегом называют раздел документации целиком,
        # поэтому слова там другие и вес у них ниже.
        def word_sets(source, role)
          return [[:strong, role.tags]] if source.key == :tag

          [[:strong, role.strong], [:weak, role.weak]]
        end

        def entry(source, kind, words)
          word = Text.find(source.tokens, words)
          return if word.nil?

          Evidence.new(
            signal: SIGNAL, detail: "#{source.label} содержит «#{word}»",
            weight: weight(kind, source.key)
          )
        end

        def weight(kind, key)
          (@weights.dig(kind.to_s, key.to_s) || 0.0).to_f
        end
      end
    end
  end
end
