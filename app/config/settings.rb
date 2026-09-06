# frozen_string_literal: true

module Config
  # Разобранная конфигурация; реализует порт Ports::Rules.
  class Settings
    # Профиль контракта: интерфейс сборки, имя класса, выходные файлы, проба.
    Contract = Struct.new(:name, :title, :class_suffix, :outputs, :probe, keyword_init: true)

    # Выходной файл профиля: шаблон и имя результата с подстановкой %<provider>s.
    Output = Struct.new(:template_name, :file, :template, keyword_init: true) do
      # @param provider [String]
      # @return [String] имя файла для этого провайдера
      def name_for(provider) = format(file, provider: provider)
    end

    # Правила роли: имя, назначение, начисление очков и исключение кандидата.
    class Role
      # Назначение роли для сценария сборки. Имена ролей задаёт контракт, признаки общие:
      # по ним разбор находит нужную роль независимо от имён.
      #
      #   calls_provider    — для роли планируется запрос к провайдеру
      #   creates_operation — роль-источник тела запроса, ограничений, авторизации и
      #                       идентификатора операции у провайдера
      #   receives_callback — тело операции описывает входящий webhook, а не запрос
      #                       к провайдеру
      TRAITS = %i[calls_provider creates_operation receives_callback].freeze

      attr_reader :name, :title, :traits, :rules, :veto, :threshold

      # @param name [String, Symbol] имя роли, оно же имя метода контракта
      # @param title [String] название роли по-русски, для отчёта и предупреждений
      # @param traits [Array<Symbol>] признаки роли из TRAITS
      # @param rules [Array<Config::Rule>] правила, дающие очки
      # @param veto [Array<Config::Rule>] правила, снимающие кандидата целиком
      # @param threshold [Integer] минимальный счёт, ниже которого роль не назначается
      def initialize(name:, title:, traits:, rules:, veto:, threshold:)
        @name = name.to_sym
        @title = title
        @traits = traits
        @rules = rules
        @veto = veto
        @threshold = threshold
      end

      # @param trait [Symbol]
      # @return [Boolean]
      def trait?(trait) = traits.include?(trait)

      # Счёт кандидата и список сработавших правил; nil при срабатывании veto.
      # @param candidate [Models::ApiOperation]
      # @return [Array(Integer, Array<Config::Rule>), nil] счёт и правила; nil при veto
      def score(candidate)
        return nil if veto.any? { |rule| rule.matches?(candidate) }

        matched = rules.select { |rule| rule.matches?(candidate) }
        [matched.sum(&:weight), matched]
      end
    end

    attr_reader :contract, :http, :role_order, :required_roles, :status_sources, :roles,
                :status_mapping, :error_mapping, :payload_fields, :requisite_fields,
                :callback_fields, :headers, :header_sources, :constraints, :path_params,
                :conditions, :auth_templates

    # Секции конфигурации записываются в одноимённые переменные.
    # @param sections [Hash{Symbol => Object}] разобранные секции конфига
    def initialize(**sections)
      sections.each { |name, value| instance_variable_set(:"@#{name}", value) }
    end

    # @param name [String, Symbol]
    # @return [Role]
    # @raise [KeyError] роль не описана в конфиге
    def role(name)
      roles.fetch(name.to_sym)
    end

    # Роли в порядке обработки классификатором.
    # @return [Array<Role>]
    def ordered_roles
      role_order.map { |name| role(name) }
    end

    # Роли с указанным признаком, в порядке обработки.
    # @param trait [Symbol] признак из Role::TRAITS
    # @return [Array<Role>]
    def roles_with(trait)
      ordered_roles.select { |role| role.trait?(trait) }
    end

    # Единственная роль с признаком; их число проверяет Importer.
    # @param trait [Symbol]
    # @return [Role, nil]
    def role_with(trait)
      roles_with(trait).first
    end

    # Обязательна ли роль: при её отсутствии сборка прерывается вместо печати заглушки.
    # @param name [String, Symbol]
    # @return [Boolean]
    def required_role?(name)
      required_roles.include?(name.to_sym)
    end

    # Состояние в терминах провайдера → статус контракта; nil, если ни один шаблон не совпал.
    # @param token [String, Symbol] состояние словом провайдера
    # @return [String, nil] статус в терминах контракта
    def contract_status(token)
      text = token.to_s.strip.downcase
      status_mapping.each do |contract_name, patterns|
        return contract_name.to_s if patterns.any? { |pattern| pattern.match?(text) }
      end
      nil
    end

    # Запись об ошибке по HTTP-коду: код, действие и символ статуса контракта.
    # @param http_code [Integer, String]
    # @return [Hash] { code:, action:, symbol: }; для неизвестного кода — значение по умолчанию
    def error_for(http_code)
      error_mapping.fetch(:codes).fetch(http_code.to_s, error_mapping.fetch(:default))
    end

    # Коды, для которых в конфигурации задан перевод; дополняют коды из описания провайдера.
    # @return [Array<Integer>]
    def known_error_codes
      error_mapping.fetch(:codes).keys.map(&:to_i).sort
    end

    # Первое правило словаря, регулярка которого совпала с именем свойства схемы.
    # @param dictionary [Array<Hash>] словарь вида { field:, source:, patterns: }
    # @param property_name [String, Symbol] имя свойства в схеме провайдера
    # @return [Hash, nil]
    def field_for(dictionary, property_name)
      dictionary.find { |entry| entry.fetch(:patterns).any? { |p| p.match?(property_name.to_s) } }
    end

    # Правило словаря по имени поля: сумма, валюта и подобные.
    # @param dictionary [Array<Hash>]
    # @param field [String, Symbol] имя поля, например :amount
    # @return [Hash, nil]
    def entry_for(dictionary, field)
      dictionary.find { |entry| entry.fetch(:field).to_s == field.to_s }
    end

    # Назначение заголовка: идемпотентность, подпись или не распознано.
    # @param name [String] имя заголовка, например Idempotency-Key
    # @return [Symbol, nil]
    def header_kind(name)
      headers.each do |kind, patterns|
        next if kind == :signature_algorithms

        return kind if patterns.any? { |pattern| pattern.match?(name.to_s) }
      end
      nil
    end

    # Выражение, которым контракт заполняет распознанный заголовок.
    # @param kind [Symbol] например :idempotency
    # @return [String, nil] выражение на Ruby
    def header_source(kind)
      header_sources[kind]
    end

    # Представление найденного ограничения в терминах контракта.
    # @param kind [Symbol] :min_amount, :max_amount или :currency
    # @return [Hash, nil] { code:, constant: }; nil — контракт такое не проверяет
    def condition(kind)
      conditions[kind.to_sym]
    end

    # Заготовка строки подписи запроса для этой схемы авторизации.
    # @param key [Symbol] например :bearer
    # @return [String, nil] шаблон, в котором ещё не подставлены имена из описания
    def auth_template(key)
      auth_templates[key]
    end
  end
end
