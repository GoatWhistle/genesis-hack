# frozen_string_literal: true

require "yaml"

module Rsocket
  module Manifest
    # Файл догадок mapping.yml.
    #
    # Это не служебный формат, а продукт: его читает инженер, который наш код в
    # глаза не видел, и по нему же он правит наши ошибки. Отсюда три требования.
    #
    # Первое: каждая догадка объяснена словами — раздел why у роли и у единиц
    # суммы говорит, что именно сработало. Второе: то, что чаще всего правят
    # руками — перевод статусов и классы ошибок, — лежит плоскими парами, а не
    # деревом с вердиктами. Третье: в файле нет ни времени создания, ни версии
    # инструмента, потому что одинаковый вход обязан давать одинаковый файл.
    class Writer
      HEADER = <<~TEXT
        # Что RSOCKET понял из описания API этого провайдера.
        #
        # Файл можно и нужно править руками: ваша правка важнее нашей догадки и
        # переживёт следующий прогон. Пустое значение означает «не определили» —
        # это честное признание, а не поломка.
        #
        # roles     — какая операция за что отвечает; why объясняет, почему мы так решили
        # money     — в чём передаётся сумма: minor это копейки, decimal это рубли
        # statuses  — статус провайдера: наш статус
        # errors    — что делать при ошибке: retryable, limit, auth, validation, final
        # webhook   — приём уведомлений и проверка подписи
        # notes     — всё, что требует вашего внимания
      TEXT

      def initialize(result, spec)
        @result = result
        @spec = spec
      end

      def write(path)
        File.write(path, to_yaml)
        path
      end

      def to_yaml
        HEADER + YAML.dump(stringify(document)).delete_prefix("---\n")
      end

      def document
        {
          "provider" => @spec.title, "spec_version" => @spec.version,
          "roles" => roles, "money" => money, "statuses" => statuses,
          "errors" => errors, "webhook" => webhook, "notes" => notes
        }
      end

      private

      def roles
        @result.roles.sort_by { |role, _| role.to_s }.to_h do |role, assignment|
          [role.to_s, {
            "operation" => where(assignment.operation), "verdict" => assignment.verdict.to_s,
            "score" => assignment.score, "why" => assignment.evidence.map(&:detail)
          }]
        end
      end

      def money
        decision = @result.money
        return { "unit" => nil, "field" => nil, "why" => [] } if decision.nil?

        {
          "unit" => decision.unit&.to_s, "field" => decision.field_path,
          "why" => decision.evidence.map(&:detail)
        }
      end

      # Статусы — самое правимое место файла, поэтому здесь плоские пары без
      # вердиктов: непереведённое видно по пустому значению, подробности лежат
      # в отчёте и в notes.
      def statuses
        @result.statuses.to_h { |status| [status.provider_value, status.canonical&.to_s] }
      end

      def errors
        {
          "by_http_code" => by_http_code, "by_provider_code" => by_provider_code
        }
      end

      def by_http_code
        @result.errors.select(&:http_code).to_h do |error|
          [error.http_code.to_s, error.klass&.to_s]
        end
      end

      def by_provider_code
        @result.errors.select(&:provider_code).to_h do |error|
          [error.provider_code, error.klass&.to_s]
        end
      end

      def webhook
        info = @result.webhook
        return nil if info.nil?

        {
          "operation" => where(info.operation), "signature_header" => info.signature_header,
          "algorithm" => info.algorithm&.to_s, "event_field" => info.event_field,
          "status_field" => info.status_field
        }
      end

      def notes
        (@spec.notes + @result.notes).map do |note|
          { "level" => note.level.to_s, "where" => note.where, "message" => note.message }
        end
      end

      def where(operation) = "#{operation.http_method.to_s.upcase} #{operation.path}"

      # Символы в YAML выглядят как `:minor` и сбивают с толку человека, который
      # правит файл руками.
      def stringify(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
        when Array then value.map { |item| stringify(item) }
        when Symbol then value.to_s
        else value
        end
      end
    end
  end
end
