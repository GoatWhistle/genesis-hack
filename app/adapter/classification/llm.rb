# frozen_string_literal: true

require "anthropic"
require "json"

module Adapter
  module Classification
    # Раздача ролей запросом в Claude. Модель получает роли контракта и операции
    # описания списками и возвращает разметку: какой роли какая операция, с какой
    # уверенностью и почему.
    #
    # Слов из правил в запросе нет — только название роли и то, что она значит для
    # сценария. Смысл ровно в этом: правила знают, что создание выплаты называют
    # create, make или submit, а модель должна узнать её сама, включая написания,
    # которых в base.yml никто не предусмотрел.
    #
    # Ответ приходит вызовом инструмента, а не текстом: разбирать разметку из
    # прозы — гадание, а схема инструмента её форму гарантирует. Инструмент не
    # навязывается (tool_choice остаётся auto): принудительный вызов несовместим
    # с рассуждениями модели, а на прокси-эндпоинтах поддержан не везде.
    class Llm
      include Service::AdapterBuilder::Ports::Classifier

      DEFAULT_MODEL = "claude-opus-5"
      # Задача простая и на один запрос: полный размах рассуждений здесь только
      # добавляет секунды. Уровень меняется переменной окружения.
      DEFAULT_EFFORT = "low"
      # Ниже этой уверенности ответ считается догадкой, и роль остаётся заглушкой:
      # пустая роль честнее неверной.
      DEFAULT_THRESHOLD = 0.6
      MAX_TOKENS = 4096

      # Claude ответил не тем, чего мы ждали, или не ответил вовсе.
      class Error < StandardError; end

      # @param rules [Ports::Rules] роли контракта
      # @param client [Anthropic::Client, nil] клиент; по умолчанию создаётся из
      #   ANTHROPIC_API_KEY и ANTHROPIC_BASE_URL при первом запросе
      # @param model [String] модель
      # @param effort [String] уровень усилий: low, medium, high, xhigh, max
      # @param threshold [Float] минимальная уверенность
      def initialize(rules, client: nil, model: ENV.fetch("RSOCKET_LLM_MODEL", DEFAULT_MODEL),
                     effort: ENV.fetch("RSOCKET_LLM_EFFORT", DEFAULT_EFFORT),
                     threshold: ENV.fetch("RSOCKET_LLM_THRESHOLD", DEFAULT_THRESHOLD).to_f)
        @rules = rules
        @client = client
        @model = model
        @effort = effort
        @threshold = threshold
      end

      # @param operations [Array<Models::ApiOperation>] все операции описания
      # @return [Hash{Symbol => Models::RoleBinding}] роль → привязка, включая заглушки
      # @raise [Error] Claude не ответил или ответил неразборчиво
      def call(operations)
        roles = @rules.ordered_roles
        return roles.to_h { |role| [role.name, empty(role)] } if operations.empty?

        assign(roles, operations, verdicts(roles, operations))
      end

      # @return [String] как классификатор называется в отчётах
      def to_s = "llm(#{@model}, effort=#{@effort})"

      private

      # Роли разбираются в порядке конфига: если модель отдала одну операцию двум
      # ролям, забирает та, что объявлена раньше, — как и у правил.
      # @param roles [Array<Config::Settings::Role>]
      # @param operations [Array<Models::ApiOperation>]
      # @param verdicts [Hash{String => Hash}] разметка модели по имени роли
      # @return [Hash{Symbol => Models::RoleBinding}]
      def assign(roles, operations, verdicts)
        claimed = []
        roles.to_h do |role|
          verdict = verdicts[role.name.to_s]
          operation = chosen(verdict, operations, claimed)
          claimed << operation if operation
          [role.name, operation ? bind(role, operation, verdict) : unbound(role, verdict)]
        end
      end

      # @param verdict [Hash, nil] что модель сказала про роль
      # @param operations [Array<Models::ApiOperation>]
      # @param claimed [Array<Models::ApiOperation>] уже занятые операции
      # @return [Models::ApiOperation, nil]
      def chosen(verdict, operations, claimed)
        return nil if verdict.nil? || confidence(verdict) < @threshold

        number = verdict["operation"].to_i
        return nil unless number.between?(1, operations.size)

        operation = operations[number - 1]
        claimed.include?(operation) ? nil : operation
      end

      # @return [Models::RoleBinding]
      def bind(role, operation, verdict)
        score = confidence(verdict)
        Models::RoleBinding.new(
          role: role, operation: operation, score: score, threshold: @threshold,
          reason: "уверенность #{score} при пороге #{@threshold}: #{verdict["reason"]}"
        )
      end

      # @return [Models::RoleBinding] заглушка: почему роль осталась пустой
      def unbound(role, verdict)
        Models::RoleBinding.new(role: role, threshold: @threshold, reason: refusal(verdict))
      end

      # @param verdict [Hash, nil]
      # @return [String]
      def refusal(verdict)
        return "модель не сказала про эту роль ничего" if verdict.nil?

        return "модель не нашла подходящей операции: #{verdict["reason"]}" if
          confidence(verdict) >= @threshold

        "уверенность #{confidence(verdict)} ниже порога #{@threshold}: #{verdict["reason"]}"
      end

      # @return [Models::RoleBinding]
      def empty(role)
        Models::RoleBinding.new(role: role, threshold: @threshold,
                                reason: "в описании нет ни одной операции")
      end

      # @param verdict [Hash]
      # @return [Float]
      def confidence(verdict) = verdict["confidence"].to_f.round(3)

      # Про одну роль модель иногда пишет несколько строк — верную и отвергнутые.
      # Оставляем ту, в которой она уверена больше всего.
      # @return [Hash{String => Hash}] разметка по имени роли
      # @raise [Error] ответ не разобрался
      def verdicts(roles, operations)
        answer = ask(Prompt.question(roles, operations))
        answer.fetch("assignments").group_by { |item| item["role"].to_s }
              .transform_values { |items| items.max_by { |item| confidence(item) } }
      rescue KeyError, NoMethodError, TypeError => e
        raise Error, "Claude ответил неразборчиво (#{e.class}): #{answer.to_s[0, 300]}"
      end

      # @param prompt [String] вопрос со списками ролей и операций
      # @return [Hash] аргументы вызванного инструмента
      # @raise [Error] запрос не удался
      def ask(prompt)
        message = client.messages.create(
          model: @model, max_tokens: MAX_TOKENS, system_: Prompt::INSTRUCTION,
          messages: [{ role: "user", content: prompt }], tools: [Prompt::TOOL],
          output_config: Anthropic::OutputConfig.new(effort: @effort)
        )
        arguments(message)
      rescue Anthropic::Errors::APIError => e
        raise Error, "Claude не ответил (#{e.class}): #{e.message}"
      end

      # @param message [Anthropic::Message]
      # @return [Hash] аргументы вызова, ключи строками на всю глубину
      # @raise [Error] модель ответила прозой вместо разметки
      def arguments(message)
        block = message.content.find { |item| item.type == :tool_use }
        # Ключи приходят символами, и вложенные записи разбором не затронуты.
        # Прогон через JSON выравнивает их разом на всю глубину.
        return JSON.parse(JSON.generate(block.input)) if block

        raise Error, "Claude не вызвал инструмент, stop_reason: #{message.stop_reason}"
      end

      # @return [Anthropic::Client] ключ и адрес берутся из окружения
      def client = @client ||= Anthropic::Client.new
    end
  end
end
