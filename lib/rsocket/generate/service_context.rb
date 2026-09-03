# frozen_string_literal: true

module Rsocket
  module Generate
    # Всё, что шаблон сервиса должен знать о провайдере.
    #
    # Шаблон намеренно глупый: он только расставляет готовые значения по
    # местам. Вся работа — разбор спецификации, сопоставление полей, перевод
    # статусов — сделана до него и проверена тестами отдельно. Иначе логика
    # расползлась бы по ERB, где её невозможно ни прочитать, ни проверить.
    ServiceContext = Data.define(
      :provider, :class_name, :env_prefix, :title, :version,
      :base_url, :base_url_env, :api_key_env, :secret_env,
      :auth, :idempotency_header,
      :create_path, :status_path, :status_path_param, :cancel_path,
      :duplicate_status, :minor_units, :amount_mode, :minimum_amount,
      :status_map, :error_map, :event_map,
      :signature, :webhook_id_field, :webhook_event_field,
      :response_id_path, :response_status_path, :error_code_path,
      :payload_source, :requisite_builders, :required_requisite_fields,
      :payout_method_field, :payout_methods,
      :skipped_optional, :manual_required, :notes
    ) do
      def initialize(**attributes)
        super(**defaults.merge(attributes))
      end

      # Уведомления есть не у всех провайдеров. У кого их нет, шаблон обязан
      # сказать об этом прямо, а не выдумать обработчик.
      def webhook?
        !signature.nil?
      end

      def cancel?
        !cancel_path.nil?
      end

      # Запрос статуса без адреса невозможен: роль не определилась.
      def status?
        !status_path.nil?
      end

      def create?
        !create_path.nil?
      end

      # Реквизиты выбираются по типу действия только там, где есть сборщики:
      # иначе аргумент контракта остался бы неиспользованным.
      def request_method_used?
        requisite_builders.any?
      end

      def payout_method?
        !payout_method_field.nil? && payout_methods.any?
      end

      # Схему входа определить не удалось: в описании её просто нет. Шаблон
      # обязан сказать об этом громко, а не подставить пустой заголовок.
      def auth_known?
        !auth[:header].nil? && !auth[:header].empty?
      end

      # Сумма передаётся строкой — такое встречается, и число вместо строки
      # провайдер отвергнет.
      def amount_as_string?
        %i[string_decimal string_minor].include?(amount_mode)
      end

      def bearer?
        auth[:prefix] && !auth[:prefix].empty?
      end

      private

      # Значения по умолчанию разнесены на два: одиночные и наборы. Так
      # видно, что отсутствие адреса или подписи — это nil, а отсутствие
      # карты — пустая карта, а не nil, и шаблону не приходится это различать.
      def defaults
        single_defaults.merge(collection_defaults)
      end

      def single_defaults
        {
          version: nil, idempotency_header: nil, create_path: nil, status_path: nil,
          status_path_param: nil, cancel_path: nil, duplicate_status: nil, minor_units: true,
          amount_mode: :minor, minimum_amount: nil, signature: nil,
          webhook_id_field: nil, webhook_event_field: nil, payout_method_field: nil
        }
      end

      def collection_defaults
        {
          status_map: {}, error_map: {}, event_map: {},
          response_id_path: ["id"], response_status_path: ["status"],
          error_code_path: %w[error code], requisite_builders: [],
          required_requisite_fields: [], payout_methods: [],
          skipped_optional: [], manual_required: [], notes: []
        }
      end
    end
  end
end
