# frozen_string_literal: true

require_relative "field_matcher"

module Rsocket
  module Generate
    # План сборки тела запроса: откуда берётся значение каждого поля.
    #
    # Это ядро генерации. Спецификация говорит, какие поля провайдер ждёт;
    # план решает, чем их заполнить из операции заказчика, а чего не знает
    # никто — и тогда поле честно помечается как требующее ручного заполнения,
    # а не набивается правдоподобной выдумкой.
    class PayloadPlan
      # Узел плана. `source` — откуда берётся значение:
      #   :amount, :currency, :external_id — поля операции заказчика
      #   :requisite                       — реквизиты получателя
      #   :object                          — вложенный объект, смотри children
      #   :manual                          — заполняет человек
      Node = Data.define(:name, :source, :children, :required, :description) do
        def initialize(**attributes)
          super(children: [], required: false, description: nil, **attributes)
        end

        def object? = source == :object
      end

      def initialize(fields, matcher: FieldMatcher.default, minor_units: true)
        @matcher = matcher
        @minor_units = minor_units
        @nodes = fields.map { |field| build(field) }
      end

      attr_reader :nodes

      # Поля, которые инструмент заполнить не смог. Уходят и в комментарии
      # сгенерированного кода, и в отчёт: молчать о них нельзя.
      def manual_fields(scope = @nodes, prefix = "")
        scope.flat_map do |node|
          path = prefix.empty? ? node.name : "#{prefix}.#{node.name}"
          next manual_fields(node.children, path) if node.object?

          node.source == :manual ? [path] : []
        end
      end

      # Объекты получателя: для каждого генерируется свой приватный сборщик.
      def requisite_objects
        @nodes.select { |node| node.children.any? && node.source == :requisite }
      end

      private

      def build(field)
        role = @matcher.role(field.name)
        return build_requisite_object(field) if role == :recipient && field.children.any?
        return build_object(field) if field.children.any?

        Node.new(name: field.name, source: leaf_source(role), required: field.required,
                 description: field.description)
      end

      # Вложенный объект получателя: его поля заполняются из реквизитов
      # операции по их собственным именам, а не по нашим догадкам.
      def build_requisite_object(field)
        children = field.children.map do |child|
          Node.new(name: child.name, source: :requisite, required: child.required,
                   description: child.description)
        end
        Node.new(name: field.name, source: :requisite, children: children,
                 required: field.required, description: field.description)
      end

      def build_object(field)
        Node.new(name: field.name, source: :object, required: field.required,
                 description: field.description, children: field.children.map { |c| build(c) })
      end

      def leaf_source(role)
        return :manual unless %i[amount currency external_id].include?(role)

        role
      end
    end
  end
end
