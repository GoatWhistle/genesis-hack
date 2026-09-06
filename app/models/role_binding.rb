# frozen_string_literal: true

module Models
  # Итог классификации по одной роли: какая операция провайдера её заняла, с каким
  # счётом и по каким правилам. Пустая привязка — повод отрендерить заглушку.
  class RoleBinding
    attr_reader :role, :operation, :score, :matched_rules, :reason

    # @param role [Config::Settings::Role] роль контракта
    # @param operation [Models::ApiOperation, nil] занявшая её операция; nil — заглушка
    # @param score [Numeric] набранный счёт: очки у правил, близость или уверенность
    #   у смысловых классификаторов
    # @param matched_rules [Array<#to_s>] сработавшие правила; у классификатора,
    #   который правил не читает, список пустой
    # @param reason [String, nil] объяснение решения своими словами. У правил его
    #   заполняет только заглушка: счёт и список правил объясняют себя сами
    # @param threshold [Numeric, nil] порог, с которым сравнивался счёт; nil — порог
    #   роли из конфига. У смысловых классификаторов своя шкала, и порог свой
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

    # Человеческое объяснение решения — уходит в mapping.yml и в комментарий кода.
    # @return [String]
    def explanation
      return reason if reason

      "счёт #{score} при пороге #{threshold}: #{matched_rules.join(", ")}"
    end
  end
end
