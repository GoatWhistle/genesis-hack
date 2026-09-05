# frozen_string_literal: true

module Controller
  # Командная строка — такой же тонкий слой над менеджером сборок, как и HTTP.
  module Cli
    # Печать сводок: что слушаем, что распозналось, что собралось. Вынесено из
    # команды: разбор аргументов и вывод — разные заботы.
    module Summary
      # Печать сводок: что слушаем, что распозналось, что собралось. Вынесено из
      # команды: разбор аргументов и вывод — разные заботы.
      # @param contract [String] имя профиля
      # @param rules [Config::Settings]
      # @param storage [Config::Storage]
      # @return [void]
      def print_rules(contract, rules, storage)
        say "контракт: #{contract} — #{rules.contract.title}"
        say "правила:  #{storage.rules}"
        rules.ordered_roles.each { |role| say "  #{role_line(rules, role)}" }
      end

      # @return [void] что слушаем и какие ручки есть
      def announce
        say "rsocket слушает http://#{options[:host]}:#{options[:port]}"
        say "  GET  /             — что умеет сервис"
        say "  GET  /health       — жив ли он"
        say "  GET  /openapi.yaml — описание этого API"
        say "  GET  /contracts    — профили контрактов и их роли"
        say "  GET  /rules        — что лежит в хранилище правил"
        say "  PUT  /rules/<ключ> — записать правила или шаблон"
        say "  POST /build        — сборка: ?provider=имя[&contract=профиль], тело — описание"
        say "хранилище: #{storage}"
      end

      # @param rules [Config::Settings]
      # @param role [Config::Settings::Role]
      # @return [String] строка сводки по роли
      def role_line(rules, role)
        required = rules.required_role?(role.name) ? "обязательна" : "необязательна"
        format("%-18<role>s порог %<threshold>2d, %<required>-15s правил: %<rules>d, %<traits>s",
               role: role.name, threshold: role.threshold, required: "#{required},",
               rules: role.rules.size, traits: role.traits.join(" "))
      end

      # @param outcome [Service::BuildManager::Assembler::Outcome]
      # @return [void]
      def print_summary(outcome)
        say "контракт: #{outcome.contract}"
        outcome.report.fetch("roles").each { |role, item| say "  #{role_state(role, item)}" }
        outcome.warnings.each { |warning| say "  ! #{warning}" }
        say ""
        outcome.locations.each { |location| say "  #{location}" }
      end

      # @param role [String] имя роли
      # @param item [Hash] раздел отчёта по этой роли
      # @return [String] строка сводки: роль и что ей досталось
      def role_state(role, item)
        format("%-18<role>s %<state>s", role: role, state: item["endpoint"] || "заглушка")
      end
    end
  end
end
