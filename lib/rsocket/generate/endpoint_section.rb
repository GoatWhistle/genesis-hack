# frozen_string_literal: true

require_relative "field_matcher"

module Rsocket
  module Generate
    # Часть контекста, отвечающая за то, куда и как сервис стучится: адреса
    # операций, схема входа, ключ идемпотентности, минимальная сумма.
    #
    # Роль может прийти неопределённой — тогда соответствующего адреса просто
    # нет, и шаблон честно пишет заглушку вместо метода. Поэтому здесь всё
    # рассчитано на отсутствующую операцию, а не на её наличие.
    class EndpointSection
      def initialize(operations, schemes:, minor_units:)
        @create = operations[:create]
        @status = operations[:status]
        @cancel = operations[:cancel]
        @schemes = schemes
        @minor_units = minor_units
      end

      def to_h
        {
          auth: auth,
          create_path: @create&.path,
          status_path: path_template(@status),
          status_path_param: path_param(@status),
          cancel_path: path_template(@cancel),
          idempotency_header: idempotency_header,
          duplicate_status: duplicate_status,
          minimum_amount: minimum_amount
        }
      end

      private

      # Схема входа берётся та, которой защищено создание выплаты: у
      # провайдера их может быть объявлено несколько.
      def auth
        scheme = @schemes.find { |s| s.id == @create&.security&.first } || @schemes.first
        return { kind: :unknown, header: nil, prefix: nil } if scheme.nil?

        { kind: scheme.kind, header: scheme.name || "Authorization",
          prefix: { bearer: "Bearer ", basic: "Basic " }[scheme.kind] }
      end

      # Фигурные скобки описания превращаются в подстановку format:
      # `/orders/{order_id}` становится `/orders/%<order_id>s`. Так адрес
      # собирается форматированием, а не склейкой строк.
      def path_template(operation)
        operation&.path&.gsub(/\{(\w+)\}/) { "%<#{Regexp.last_match(1)}>s" }
      end

      def path_param(operation)
        params = operation&.path_params
        params&.first&.name
      end

      def idempotency_header
        header = @create&.header_params&.find { |field| field.name.match?(/idempot/i) }
        header&.name
      end

      # Ответ 409 у создания выплаты — повтор по ключу идемпотентности, а не
      # сбой, но только если провайдер отдаёт по нему тот же ресурс.
      def duplicate_status
        return nil unless idempotency_header && @create&.responses&.key?(409)

        @create.responses[409].fields.any? ? 409 : nil
      end

      # Минимальная сумма остаётся ровно в тех единицах, в которых её объявил
      # провайдер, и сравнивается с уже переведённой суммой. Пересчёт в
      # основные единицы у провайдера с минимумом в одну копейку дал бы ноль
      # на целочисленном делении, и проверка молча исчезла бы.
      def minimum_amount
        matcher = FieldMatcher.default
        field = leaves(@create&.request_fields || []).find { |f| matcher.role?(f.name, :amount) }
        field&.minimum
      end

      def leaves(fields)
        fields.flat_map { |field| field.children.any? ? leaves(field.children) : [field] }
      end
    end
  end
end
