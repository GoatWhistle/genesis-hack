# frozen_string_literal: true

module Models
  # Результат классификации роли; пустая привязка означает заглушку.
  class RoleBinding
    attr_reader :role, :operation, :score, :matched_rules, :reason

    # @param role [Config::Settings::Role] роль контракта
    # @param operation [Models::ApiOperation, nil] занявшая роль операция; nil — заглушка
    # @param score [Numeric] набранный счёт: очки правил либо близость или уверенность
    #   смыслового классификатора
    # @param matched_rules [Array<#to_s>] сработавшие правила; пустой список у
    #   классификаторов, не использующих правила
    # @param reason [String, nil] текстовое объяснение решения. У правил заполняется
    #   только для незанятой роли: счёт и список правил объясняют решение сами
    # @param threshold [Numeric, nil] порог сравнения счёта; nil — порог роли из
    #   конфигурации. У смысловых классификаторов своя шкала и свой порог
    def initialize(role:, operation: nil, score: 0, matched_rules: [], reason: nil,
                   threshold: nil)
      @role = role
      @operation = operation
      @score = score
      @matched_rules = matched_rules
      @reason = reason
      @threshold = threshold
    end

    # @return [Boolean] нашлась ли операция под роль
    def bound?
      !operation.nil?
    end

    # @return [Numeric] порог, ниже которого роль не назначается
    def threshold = @threshold || role.threshold

    # @return [String] эндпоинт роли: POST /payouts
    def endpoint
      "#{operation.http_method.upcase} #{operation.path}"
    end

    # @return [Symbol] например :create_request
    def role_name
      role.name
    end

    # Текстовое объяснение решения; записывается в mapping.yml и в комментарий кода.
    # @return [String]
    def explanation
      return reason if reason

      "счёт #{score} при пороге #{threshold}: #{matched_rules.join(", ")}"
    end
  end
end
