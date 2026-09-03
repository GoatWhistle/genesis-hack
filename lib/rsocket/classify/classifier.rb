# frozen_string_literal: true

require_relative "../dictionaries"
require_relative "error_mapper"
require_relative "money_detector"
require_relative "result"
require_relative "role_matcher"
require_relative "roles"
require_relative "scoring"
require_relative "signals/lexicon"
require_relative "signals/lifecycle"
require_relative "signals/signature"
require_relative "status_mapper"
require_relative "webhook_detector"

module Rsocket
  module Classify
    # Разбор смысла описания целиком: роли операций, статусы, ошибки, единицы
    # суммы и приём уведомлений.
    #
    # Каждый вывод сопровождается признаками, записанными словами. Мы нигде не
    # печатаем «уверенность 0.87»: инженер читает, что именно сработало, и сам
    # решает, согласен ли он. Это же и ответ на вопрос «а если инструмент
    # ошибётся» — ошибётся заметно и объяснимо.
    class Classifier
      # Признаки складываются, а не выбирают друг друга: три независимых способа
      # догадаться сильнее одного точного.
      DEFAULT_SIGNALS = [Signals::Lexicon, Signals::Signature, Signals::Lifecycle].freeze

      def self.call(spec, **)
        new(spec, **).call
      end

      def initialize(spec, dictionaries: Rsocket::Dictionaries.default, signals: DEFAULT_SIGNALS)
        @context = Context.new(
          spec: spec, dictionaries: dictionaries, roles: Roles.default(dictionaries)
        )
        @signals = signals.map { |signal| signal.new(@context) }
        @scoring = Scoring.new(dictionaries.weights)
      end

      def call
        matched = RoleMatcher.new(@context, @signals, @scoring).call
        statuses = StatusMapper.new(@context).call
        errors = ErrorMapper.new(@context).call
        money = MoneyDetector.new(@context).call
        webhook = WebhookDetector.new(@context).call
        build(matched, statuses, errors, money, webhook)
      end

      private

      def build(matched, statuses, errors, money, webhook)
        Result.new(
          roles: matched.assignments.to_h { |item| [item.role, item] },
          statuses: statuses, errors: errors, money: money, webhook: webhook,
          notes: matched.notes + gaps(statuses, errors, money, webhook)
        )
      end

      # Всё, чего мы не поняли, обязано быть названо вслух. Молча пропущенный
      # статус или неопознанный класс ошибки — это тихая ошибка в бою.
      def gaps(statuses, errors, money, webhook)
        [
          untranslated_statuses(statuses), unclassified_errors(errors),
          unknown_money(money), unsigned_webhook(webhook)
        ].compact
      end

      def untranslated_statuses(statuses)
        values = statuses.select { |status| status.canonical.nil? }.map(&:provider_value)
        return if values.empty?

        note("components.schemas",
             "Статусы провайдера без перевода: #{values.join(", ")}. Допишите перевод " \
             "в файле догадок, иначе готовый код не поймёт эти значения")
      end

      def unclassified_errors(errors)
        codes = errors.select { |error| error.klass.nil? }.filter_map(&:provider_code)
        return if codes.empty?

        note("components.schemas",
             "Коды ошибок без класса: #{codes.join(", ")}. Пока для них не решено, " \
             "стоит ли повторять запрос")
      end

      def unknown_money(money)
        return if money.nil? || !money.unit.nil?

        note("paths", "Единицы суммы не определены. Это самое опасное место интеграции: " \
                      "укажите их вручную в файле догадок")
      end

      def unsigned_webhook(webhook)
        return if webhook.nil? || (webhook.algorithm != :unknown && !webhook.signature_header.nil?)

        note("paths", "Уведомления приходят, но способ подписи из описания не восстановлен. " \
                      "Проверять подпись наугад нельзя — задайте алгоритм вручную")
      end

      def note(where, message)
        Rsocket::Ir::Note.new(level: :needs_confirmation, where: where, message: message)
      end
    end
  end
end
