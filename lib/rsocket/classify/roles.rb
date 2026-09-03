# frozen_string_literal: true

require_relative "../dictionaries"

module Rsocket
  module Classify
    # Каноническая роль операции: что она делает с точки зрения интеграции.
    Role = Data.define(:id, :title, :strong, :weak, :tags) do
      def initialize(**attributes)
        defaults = { strong: [], weak: [], tags: [] }
        super(**defaults.merge(attributes))
      end
    end

    # Реестр ролей, собранный из словаря.
    #
    # Ни одна роль здесь не названа: список целиком приходит из
    # dictionaries/operations.yml. Появится седьмая роль — код не изменится,
    # изменится словарь. Это же правило проверяет тест на зашитые названия.
    class Roles
      include Enumerable

      def self.default(dictionaries = Rsocket::Dictionaries.default)
        new(dictionaries.operations)
      end

      def initialize(source)
        @roles = build(source)
      end

      def each(&) = @roles.each(&)

      def [](id) = @roles.find { |role| role.id == id }

      def ids = @roles.map(&:id)

      def title(id) = self[id]&.title || id.to_s

      private

      def build(source)
        raise Rsocket::Error, "словарь ролей пуст" if source.nil? || source.empty?

        source.map do |id, definition|
          Role.new(
            id: id.to_sym, title: definition["title"] || id.to_s,
            strong: Array(definition["strong"]), weak: Array(definition["weak"]),
            tags: Array(definition["tags"])
          )
        end
      end
    end
  end
end
