# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Classification
      # Роль и операция словами: смысловым классификаторам нужен текст, а не регулярки.
      module Wording
        # Поля с лексикой; http_method и форма пути слов не несут.
        MEANINGFUL = %w[method_name operation_id summary description tags].freeze

        # Признаки роли словами: модели нужны слова, а не символы из TRAITS.
        TRAITS = {
          calls_provider: "сервис сам отправляет такой запрос провайдеру",
          creates_operation: "с этой операции выплата начинается",
          receives_callback: "это входящее уведомление, его присылает провайдер"
        }.freeze

        # Длинные описания усекаются: дальше идут детали схемы.
        LIMIT = 600

        # Отрицательный просмотр перечисляет то, чем роль НЕ является: слова из такого
        # правила в эталон брать нельзя.
        NEGATIVE = /\(\?<?!/

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

        # Слова из правил роли: регулярка вида (create|make|submit) содержит перечень синонимов.
        # @param role [Config::Settings::Role]
        # @return [String, nil]
        def synonyms(role)
          words = role.rules.select { |rule| synonymous?(rule) }
                      .flat_map { |rule| literals(rule.pattern.source) }.uniq
          words.empty? ? nil : "называется так: #{words.join(", ")}"
        end

        # @param rule [Config::Rule]
        # @return [Boolean] перечисляет ли правило синонимы роли
        def synonymous?(rule)
          MEANINGFUL.include?(rule.field) && !NEGATIVE.match?(rule.pattern.source)
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
