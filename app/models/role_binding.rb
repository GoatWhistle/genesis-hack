# frozen_string_literal: true

module Models
  # Итог классификации по одной роли: какая операция провайдера её заняла, с каким
  # счётом и по каким правилам. Пустая привязка — повод отрендерить заглушку.
  class RoleBinding
    attr_reader :role, :operation, :score, :matched_rules, :reason

    # @param role [Config::Settings::Role] роль контракта
    # @param operation [Models::ApiOperation, nil] занявшая её операция; nil — заглушка
    # @param score [Integer] набранный счёт
    # @param matched_rules [Array<Config::Rule>] сработавшие правила
    # @param reason [String, nil] почему роль осталась незанятой
    def initialize(role:, operation: nil, score: 0, matched_rules: [], reason: nil)
      @role = role
      @operation = operation
      @score = score
      @matched_rules = matched_rules
      @reason = reason
    end

    # @return [Boolean] нашлась ли операция под роль
    def bound?
      !operation.nil?
    end

    # @return [String] эндпоинт роли: POST /payouts
    def endpoint
      "#{operation.http_method.upcase} #{operation.path}"
    end

    # @return [Symbol] например :create_request
    def role_name
      role.name
    end

    # Человеческое объяснение решения — уходит в mapping.yml и в комментарий кода.
    # @return [String]
    def explanation
      return reason unless bound?

      "счёт #{score} при пороге #{role.threshold}: #{matched_rules.join(", ")}"
    end
  end
end
