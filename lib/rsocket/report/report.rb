# frozen_string_literal: true

require_relative "../classify/roles"

module Rsocket
  module Report
    # Одна находка отчёта: заголовок и объяснение словами.
    Finding = Data.define(:title, :details) do
      def initialize(**attributes)
        defaults = { details: [] }
        super(**defaults.merge(attributes))
      end
    end

    # Отчёт о разборе: три ведра — понято уверенно, требует подтверждения, не
    # поддержано.
    #
    # Пункт критериев «система сообщает о неподдерживаемых или неоднозначных
    # элементах» закрывается именно этим. Поэтому здесь собирается всё: и
    # находки классификатора, и заметки загрузчика, которые тот оставил ещё на
    # этапе чтения файла. Молча пропустить нельзя ничего.
    class Report
      Sections = Data.define(:confident, :needs_confirmation, :unsupported)

      def initialize(spec, result, roles: nil)
        @spec = spec
        @result = result
        @roles = roles || Rsocket::Classify::Roles.default
      end

      def sections
        Sections.new(
          confident: confident, needs_confirmation: needs_confirmation, unsupported: unsupported
        )
      end

      def title = [@spec.title, @spec.version].compact.join(" ")

      def summary
        "операций: #{@spec.operations.size}; ролей определено: " \
          "#{@result.roles.size} из #{@roles.ids.size}"
      end

      private

      def confident
        role_findings(:confident) + money_finding(:confident) +
          status_finding(:confident) + error_finding + webhook_finding(:confident)
      end

      def needs_confirmation
        role_findings(:needs_confirmation) + money_finding(:needs_confirmation) +
          status_finding(:needs_confirmation) + webhook_finding(:needs_confirmation) +
          note_findings(:needs_confirmation) + note_findings(:info)
      end

      def unsupported
        note_findings(:unsupported)
      end

      def role_findings(verdict)
        @result.roles.values.select { |item| item.verdict == verdict }.map do |assignment|
          Finding.new(
            title: "#{@roles.title(assignment.role)} → #{where(assignment.operation)}",
            details: assignment.evidence.map(&:detail)
          )
        end
      end

      def money_finding(verdict)
        money = @result.money
        return [] if money.nil?
        return [] if (verdict == :confident) != !money.unit.nil?

        [Finding.new(title: money_title(money), details: money.evidence.map(&:detail))]
      end

      def money_title(money)
        return "единицы суммы не определены" if money.unit.nil?

        units = money.unit == :minor ? "в минимальных единицах" : "дробным числом"
        "сумма передаётся #{units} (поле «#{money.field_path}»)"
      end

      # Статусы показываем одной строкой на все переводы: две дюжины отдельных
      # находок утопили бы всё остальное.
      def status_finding(verdict)
        translated = @result.statuses.select { |status| status.verdict == verdict }
        return [] if translated.empty?

        [Finding.new(
          title: "статусы провайдера (#{translated.size})",
          details: translated.map { |status| status_line(status) }
        )]
      end

      def status_line(status)
        "#{status.provider_value} → #{status.canonical || "не определено, впишите вручную"}"
      end

      def error_finding
        classified = @result.errors.reject { |error| error.klass.nil? }
        return [] if classified.empty?

        [Finding.new(
          title: "обработка ошибок (#{classified.size})",
          details: classified.map { |error| error_line(error) }
        )]
      end

      def error_line(error)
        "#{error.http_code || error.provider_code} → #{error.klass}"
      end

      def webhook_finding(verdict)
        info = @result.webhook
        return [] if info.nil?

        known = info.algorithm != :unknown && !info.signature_header.nil?
        return [] if (verdict == :confident) != known

        [Finding.new(title: "проверка подписи уведомлений → #{where(info.operation)}",
                     details: webhook_details(info))]
      end

      def webhook_details(info)
        [
          "подпись в заголовке «#{info.signature_header || "не найден"}», " \
          "алгоритм #{info.algorithm}",
          "поле события «#{info.event_field}», поле статуса «#{info.status_field}»"
        ]
      end

      # Заметки приходят и от разбора файла, и от разбора смысла: для человека
      # это один список, и делить его по тому, кто из нас споткнулся, незачем.
      def note_findings(level)
        notes(level).map { |note| Finding.new(title: note.message, details: [note.where].compact) }
      end

      def notes(level)
        (@spec.notes + @result.notes).select { |note| note.level == level }
      end

      def where(operation) = "#{operation.http_method.to_s.upcase} #{operation.path}"
    end
  end
end
