# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Classification
      # Роль и операция словами. Классификаторы на правилах сверяют регулярки, а
      # те, что читают смысл (эмбеддинги, LLM), работают с текстом — и текст этот
      # нужно откуда-то взять, не заводя третьего описания ролей в конфиге.
      #
      # Эталон роли собирается из того же, что уже описано в правилах: названия
      # роли, её признаков и слов, которыми провайдеры называют такую операцию.
      # Слова достаются из регулярок архетипа — там они и перечислены. Добавили
      # в base.yml новый синоним — его увидят все три классификатора сразу.
      module Wording
        # Поля, по которым правила ловят смысл. Регулярки по http_method и по
        # форме пути смысла не несут — из них слов не берём.
        MEANINGFUL = %w[operation_id summary description tags].freeze

        # Что признак роли значит по-русски: эмбеддингу и модели нужны слова, а не
        # символы из TRAITS.
        TRAITS = {
          calls_provider: "сервис сам отправляет такой запрос провайдеру",
          creates_operation: "с этой операции выплата начинается",
          receives_callback: "это входящее уведомление, его присылает провайдер"
        }.freeze

        # Длинные описания операций режем: дальше первых строк идут детали схемы,
        # которые размывают вектор и стоят денег.
        LIMIT = 600

        module_function

        # @param role [Config::Settings::Role] роль контракта
        # @return [String] эталонное описание роли
        def role(role)
          [role.title, traits(role), synonyms(role)].compact.join(". ")
        end

        # @param operation [Models::ApiOperation] операция провайдера
        # @return [String] то же самое про операцию: имя, адрес и слова автора
        def operation(operation)
          parts = [operation.method_name, "#{operation.http_method.upcase} #{operation.path}",
                   operation.summary, operation.description,
                   tags(operation)]
          parts.compact.reject(&:empty?).join(". ")[0, LIMIT]
        end

        # @param role [Config::Settings::Role]
        # @return [String, nil] признаки роли словами
        def traits(role)
          words = role.traits.filter_map { |trait| TRAITS[trait] }
          words.empty? ? nil : words.join(", ")
        end

        # Слова из правил роли: регулярка вида (create|make|submit) — это и есть
        # перечень синонимов, ради которого правила писались.
        # @param role [Config::Settings::Role]
        # @return [String, nil]
        def synonyms(role)
          words = role.rules.select { |rule| MEANINGFUL.include?(rule.field) }
                      .flat_map { |rule| literals(rule.pattern.source) }.uniq
          words.empty? ? nil : "называется так: #{words.join(", ")}"
        end

        # @param source [String] исходник регулярки
        # @return [Array<String>] слова длиннее двух букв, латиница и кириллица
        def literals(source)
          source.scan(/[[:alpha:]]{3,}/)
        end

        # @param operation [Models::ApiOperation]
        # @return [String, nil]
        def tags(operation)
          tags = Array(operation.tags).compact
          tags.empty? ? nil : "теги: #{tags.join(", ")}"
        end
      end
    end
  end
end
