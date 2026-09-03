# frozen_string_literal: true

require_relative "field_matcher"
require_relative "payload_plan"
require_relative "payload_renderer"

module Rsocket
  module Generate
    # Часть контекста, отвечающая за тело запроса: исходный текст сборки,
    # приватные сборщики реквизитов, обязательные поля и способы выплаты.
    #
    # Вынесено из сборщика контекста отдельно, потому что это самостоятельная
    # работа со своим входом (поля тела запроса) и своим выходом (готовые
    # куски кода). Заодно сборщик контекста остаётся обозримым.
    class PayloadSection
      # Слова, которыми в описаниях задают условную обязательность поля.
      CONDITIONAL_HINT = /обязател|required|если|when|for type|при\s/i

      def initialize(operation, minor_units:)
        @fields = operation&.request_fields || []
        @minor_units = minor_units
        @plan = PayloadPlan.new(@fields)
        @renderer = PayloadRenderer.new(@plan, amount_mode: amount_mode)
      end

      def to_h
        {
          payload_source: @renderer.call,
          amount_mode: amount_mode,
          requisite_builders: builders,
          required_requisite_fields: required_requisite,
          payout_method_field: method_field&.name,
          payout_methods: method_field&.enum || [],
          skipped_optional: @renderer.skipped_optional,
          manual_required: @plan.manual_fields
        }
      end

      def notes
        [manual_note, conditional_note].compact
      end

      private

      # Как передавать сумму. Тип поля важнее единиц: провайдер, объявивший
      # сумму строкой, отвергнет число, каким бы верным оно ни было.
      def amount_mode
        @amount_mode ||= begin
          field = amount_leaf
          string = field&.type.to_s == "string"
          if string
            @minor_units ? :string_minor : :string_decimal
          else
            @minor_units ? :minor : :decimal
          end
        end
      end

      def amount_leaf
        matcher = FieldMatcher.default
        leaves(@fields).find { |field| matcher.role?(field.name, :amount) }
      end

      def builders
        @plan.requisite_objects.map do |node|
          { method: "build_#{FieldMatcher.normalize(node.name)}", field: node.name,
            keys: node.children.map { |child| { name: child.name, required: child.required } } }
        end
      end

      def required_requisite
        @plan.requisite_objects.flat_map { |node| node.children.select(&:required).map(&:name) }
      end

      # Поле, выбирающее способ выплаты: перечисление внутри реквизитов
      # получателя. Именно им и управляет `request_method` — логический тип
      # действия шлюза, а не HTTP-глагол.
      def method_field
        @method_field ||= find_method_field
      end

      def find_method_field
        names = @plan.requisite_objects.map(&:name)
        object = @fields.find { |field| names.include?(field.name) }
        object&.children&.find { |child| enum?(child) }
      end

      def enum?(field)
        !field.enum.nil? && !field.enum.empty?
      end

      def manual_note
        skipped = @renderer.skipped_optional
        return nil if skipped.empty?

        "поля не связаны с операцией и не отправляются: #{skipped.join(", ")}"
      end

      # Условие вида «поле обязательно при таком-то способе выплаты» пишут
      # текстом описания, а не структурой. Автоматически вычитать его нельзя,
      # но и промолчать нельзя тоже: молча угадывать критичное хуже, чем
      # честно сказать «здесь неоднозначно».
      def conditional_note
        suspect = leaves(@fields).reject(&:required)
                                 .select { |f| f.description.to_s.match?(CONDITIONAL_HINT) }
        return nil if suspect.empty?

        "необязательные по структуре поля, у которых в описании есть условие " \
          "обязательности — проверьте руками: #{suspect.map(&:path).join(", ")}"
      end

      def leaves(fields)
        fields.flat_map { |field| field.children.any? ? leaves(field.children) : [field] }
      end
    end
  end
end
