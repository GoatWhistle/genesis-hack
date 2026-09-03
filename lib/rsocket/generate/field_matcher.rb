# frozen_string_literal: true

require "yaml"

module Rsocket
  module Generate
    # Сопоставление имён полей провайдера с ролями, которые они играют.
    #
    # Механизм здесь, знание — в field_sources.yml. Добавление синонима не
    # требует правки этого файла, и это проверяется тестом.
    #
    # Сравнение идёт по нормализованному имени: `orderNo`, `order_no` и
    # `OrderNO` — одно слово. Иначе пришлось бы держать в словаре все три
    # написания каждого синонима, а спецификации пишут кто во что горазд.
    class FieldMatcher
      SOURCES_FILE = "field_sources.yml"

      def self.default
        @default ||= new(YAML.safe_load_file(File.join(__dir__, SOURCES_FILE)))
      end

      def initialize(sources)
        @synonyms = sources.transform_values { |names| names.map { |n| self.class.normalize(n) } }
      end

      # Имя поля к общему виду: camelCase разбивается, регистр снимается,
      # разделители схлопываются.
      def self.normalize(name)
        name.to_s
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
            .gsub(/[^a-z\d]+/, "_")
            .gsub(/\A_+|_+\z/, "")
      end

      # Роль поля или nil, если ни один синоним не подошёл. Нет совпадения —
      # значит поле остаётся человеку, и это честнее выдумывания.
      def role(name)
        normalized = self.class.normalize(name)
        @synonyms.each { |role, names| return role.to_sym if names.include?(normalized) }
        nil
      end

      def role?(name, expected)
        role(name) == expected.to_sym
      end
    end
  end
end
