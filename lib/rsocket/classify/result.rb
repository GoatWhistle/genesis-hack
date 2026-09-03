# frozen_string_literal: true

require_relative "../ir"

module Rsocket
  module Classify
    # Что мы поняли про одну операцию: какая роль, насколько уверенно и почему.
    RoleAssignment = Data.define(:role, :operation, :score, :verdict, :evidence) do
      def initialize(**attributes)
        defaults = { score: 0.0, verdict: :unknown, evidence: [] }
        super(**defaults.merge(attributes))
      end

      def confident? = verdict == :confident
    end

    # Статус провайдера и наш канонический.
    StatusMapping = Data.define(:provider_value, :canonical, :verdict, :evidence) do
      def initialize(**attributes)
        defaults = { canonical: nil, verdict: :unknown, evidence: [] }
        super(**defaults.merge(attributes))
      end
    end

    # Ошибка провайдера и то, как с ней обращаться вызывающему коду.
    ErrorMapping = Data.define(:http_code, :provider_code, :klass, :evidence) do
      def initialize(**attributes)
        defaults = { http_code: nil, provider_code: nil, klass: nil, evidence: [] }
        super(**defaults.merge(attributes))
      end
    end

    # В чём передаётся сумма. Отдельный тип, потому что цена ошибки здесь выше,
    # чем у любой другой догадки: перевод уйдёт в сто раз больше или меньше.
    MoneyDecision = Data.define(:unit, :field_path, :evidence) do
      def initialize(**attributes)
        defaults = { unit: nil, field_path: nil, evidence: [] }
        super(**defaults.merge(attributes))
      end
    end

    # Приём уведомлений: где подпись, чем подписано, какие поля читать.
    WebhookInfo = Data.define(
      :operation, :signature_header, :algorithm, :event_field, :status_field
    ) do
      def initialize(**attributes)
        defaults = {
          signature_header: nil, algorithm: :unknown, event_field: nil, status_field: nil
        }
        super(**defaults.merge(attributes))
      end
    end

    # Всё, что поняли по описанию. Дальше по конвейеру это принимают шаблоны и
    # файл догадок, поэтому набор полей — общая договорённость команды и меняется
    # только с записью в журнал.
    Result = Data.define(:roles, :statuses, :errors, :money, :webhook, :notes) do
      def initialize(**attributes)
        defaults = {
          roles: {}, statuses: [], errors: [], money: nil, webhook: nil, notes: []
        }
        super(**defaults.merge(attributes))
      end

      def role(id) = roles[id]

      def confident_roles = roles.select { |_id, assignment| assignment.confident? }
    end

    # Общее, что нужно каждому признаку помимо самой операции.
    Context = Data.define(:spec, :dictionaries, :roles)
  end
end
