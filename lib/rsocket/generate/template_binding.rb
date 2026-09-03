# frozen_string_literal: true

require "forwardable"

require_relative "service_context"
require_relative "translation"

module Rsocket
  module Generate
    # Обёртка контекста для шаблона: сам контекст плюс несколько помощников,
    # печатающих исходный текст на Ruby.
    #
    # Помощники живут здесь, а не в шаблоне, по той же причине, по которой в
    # шаблоне нет логики: печать хеша с переносом длинных строк — это код, и
    # его надо уметь прочитать и проверить тестом, а не вычитывать из ERB.
    class TemplateBinding
      extend Forwardable

      # Ширина, после которой запись карты ошибок переносится. Меньше предела
      # линтера: к строке ещё добавится отступ вложенности.
      WRAP_AT = 96

      CUSTOMER_CONSTANTS = {
        Translation::IN_PROGRESS => "BaseService::IN_PROGRESS",
        Translation::APPROVED => "BaseService::APPROVED",
        Translation::REJECTED => "BaseService::REJECTED"
      }.freeze

      WORD = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

      # Делегируется всё, что умеет контекст, а не перечисленный руками
      # список: список пришлось бы дополнять при каждом новом поле, и шаблон
      # падал бы на ровном месте уже дважды по этой причине.
      def_delegators :@context, *(ServiceContext.instance_methods - Object.instance_methods)

      def initialize(context)
        @context = context
      end

      def erb_binding
        binding
      end

      # Карта «значение провайдера → статус заказчика» константами, а не
      # строками: опечатка в строке молчит, опечатка в имени константы падает.
      def render_status_map(indent)
        render_pairs(status_map, indent) do |value, customer|
          "#{value.inspect} => #{CUSTOMER_CONSTANTS.fetch(customer, customer.inspect)}"
        end
      end

      def render_event_map(indent)
        render_pairs(event_map, indent) do |event, customer|
          "#{event.inspect} => #{CUSTOMER_CONSTANTS.fetch(customer, customer.inspect)}"
        end
      end

      def render_error_map(indent)
        render_pairs(error_map, indent) { |code, entry| error_entry(code, entry, indent) }
      end

      # Массив строк печатается %w[...], если все элементы — обычные слова:
      # так требует линтер, и так читается лучше.
      def string_array(values)
        return "[]" if values.empty?
        return "%w[#{values.join(" ")}]" if values.all? { |v| v.to_s.match?(WORD) }

        "[#{values.map(&:inspect).join(", ")}]"
      end

      private

      def render_pairs(hash, indent)
        pad = " " * indent
        hash.map { |key, value| "#{pad}#{yield(key, value)}" }.join(",\n")
      end

      # Длинная запись переносится перед действием: три ключа в строку не
      # влезают у половины провайдеров, а линтер за это ругается.
      def error_entry(code, entry, indent)
        head = "#{code} => { code: #{entry[:code].inspect}, status: #{entry[:status].inspect}"
        tail = "action: #{entry[:action].inspect} }"
        single = "#{head}, #{tail}"
        return single if single.length + indent <= WRAP_AT

        "#{head},\n#{" " * (indent + code.to_s.length + 7)}#{tail}"
      end
    end
  end
end
