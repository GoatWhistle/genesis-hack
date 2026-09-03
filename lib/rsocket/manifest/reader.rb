# frozen_string_literal: true

require "yaml"

require_relative "../classify/result"
require_relative "../errors"
require_relative "overrides"

module Rsocket
  module Manifest
    # Чтение файла догадок обратно.
    #
    # Главное правило: правка человека важнее нашей догадки. Инженер, поправивший
    # роль или перевод статуса, не должен получить свою правку обратно затёртой
    # на следующем прогоне — иначе файл бесполезен, а инструмент навязчив.
    #
    # Ключи здесь общие механизмы, а не названия провайдера: роль, единицы
    # суммы, класс ошибки, способ подписи. Ключ с именем провайдера в названии
    # был бы привязкой к нему, а такой — настройкой инструмента.
    class Reader
      SIGNAL = :manifest

      def self.load(path)
        return if path.nil? || !File.file?(path)

        new(YAML.safe_load_file(path) || {})
      rescue Psych::SyntaxError => e
        raise Rsocket::Error, "файл догадок не читается: #{e.message}"
      end

      def initialize(document)
        @document = document || {}
      end

      def apply(result, spec)
        @spec = spec
        @notes = []
        values = Overrides.new(@document)
        result.with(
          roles: roles(result.roles), statuses: values.statuses(result.statuses),
          errors: values.errors(result.errors), money: values.money(result.money),
          webhook: values.webhook(result.webhook), notes: result.notes + @notes
        )
      end

      private

      def section(name) = @document[name].is_a?(Hash) ? @document[name] : {}

      def roles(computed)
        section("roles").each_with_object(computed.dup) do |(role, override), roles|
          next unless override.is_a?(Hash) && override.key?("operation")

          apply_role(roles, role.to_sym, override["operation"])
        end
      end

      # Переопределяем только то, что отличается от нашего вывода. Файл,
      # записанный прошлым прогоном, — это не правка человека, и принимать его
      # за правку означает терять обоснования на втором же запуске.
      def apply_role(roles, role, where)
        return roles.delete(role) if where.nil? || where.to_s.strip.empty?
        return if same_operation?(roles[role], where)

        operation = find_operation(where)
        return missing_operation(where) if operation.nil?

        roles[role] = Rsocket::Classify::RoleAssignment.new(
          role: role, operation: operation, score: 0.0, verdict: :confident,
          evidence: [evidence("роль задана человеком в файле догадок: #{where}")]
        )
      end

      def same_operation?(assignment, where)
        return false if assignment.nil?

        operation = assignment.operation
        "#{operation.http_method.to_s.upcase} #{operation.path}" == where.to_s.strip
      end

      def find_operation(where)
        method, path = where.to_s.split(" ", 2)
        @spec.operations.find do |operation|
          operation.http_method.to_s.casecmp?(method.to_s) && operation.path == path
        end
      end

      def missing_operation(where)
        @notes << note("в файле догадок указана операция «#{where}», которой нет в описании; " \
                       "оставлен автоматический вывод")
        nil
      end

      def evidence(detail)
        Rsocket::Classify::Evidence.new(signal: SIGNAL, weight: 0.0, detail: detail)
      end

      def note(message)
        Rsocket::Ir::Note.new(level: :needs_confirmation, where: "mapping.yml", message: message)
      end
    end
  end
end
