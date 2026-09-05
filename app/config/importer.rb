# frozen_string_literal: true

require "yaml"
require "pathname"

module Config
  # Импорт конфигурации: общие правила распознавания плюс профиль контракта →
  # Settings. Профиль решает, под какой интерфейс собирается класс: как называются
  # роли, какими словами говорит контракт и по какому шаблону печатается результат.
  class Importer
    # Сколько ролей может нести признак: на создающей операцию завязаны тело
    # запроса, лимиты и авторизация, на принимающей webhook — разбор колбэка.
    CARDINALITY = {
      creates_operation: [1..1, "ровно одна роль"],
      receives_callback: [0..1, "не больше одной роли"]
    }.freeze

    # @param contract [String, Symbol] имя профиля контракта
    # @return [Settings]
    def self.call(contract = Catalog.default)
      new(contract).call
    end

    # @param contract [String, Symbol] имя профиля контракта
    # @param catalog [Catalog] где искать профили
    def initialize(contract = Catalog.default, catalog: Catalog.new)
      @name = contract.to_s
      @catalog = catalog
    end

    # Читает оба файла и собирает правила разбора.
    # @return [Settings]
    # @raise [ArgumentError] профиля нет, файла нет или признак роли неизвестен
    # @raise [KeyError] в конфиге не хватает обязательной секции
    def call
      base = parse(@catalog.base)
      contract = parse(@catalog.contract(@name))
      classification = classification(base, contract)
      vocabulary = Vocabulary.new(base, contract)

      Settings.new(contract: meta(contract), http: contract.fetch(:http), **classification,
                   **vocabulary.mappings, **vocabulary.dictionaries)
    end

    private

    # @param content [String] содержимое конфига из хранилища
    # @return [Hash] разобранный YAML, ключи символами
    def parse(content)
      YAML.safe_load(content, aliases: true, symbolize_names: true)
    end

    # @param contract [Hash] разобранный contract.yml
    # @return [Settings::Contract] чем контракт представляется наружу
    def meta(contract)
      section = contract.fetch(:contract)
      Settings::Contract.new(
        name: @name, title: section.fetch(:title), class_suffix: section.fetch(:class_suffix),
        outputs: outputs(section.fetch(:outputs))
      )
    end

    # Шаблоны читаются здесь же: печатать всё равно придётся все, а хранилище
    # может быть удалённым — лучше сходить в него один раз при загрузке правил.
    # @param entries [Array<Hash>] записи { template:, file: }
    # @return [Array<Settings::Output>] имя файла шаблона, имя результата и сам шаблон
    def outputs(entries)
      entries.map do |entry|
        name = entry.fetch(:template)
        Settings::Output.new(template_name: name, file: entry.fetch(:file),
                             template: @catalog.template(@name, name))
      end
    end

    # @param base [Hash] разобранный base.yml
    # @param contract [Hash] разобранный contract.yml
    # @return [Hash] секции role_order, required_roles, status_sources и roles
    def classification(base, contract)
      section = contract.fetch(:classification)
      {
        role_order: symbols(section.fetch(:order)),
        required_roles: symbols(section.fetch(:required)),
        status_sources: symbols(section.fetch(:status_sources)),
        roles: check(build_roles(base.fetch(:archetypes), section))
      }
    end

    # @param archetypes [Hash] архетипы операций из base.yml
    # @param section [Hash] секция classification контракта
    # @return [Hash{Symbol => Settings::Role}]
    def build_roles(archetypes, section)
      thresholds = section.fetch(:thresholds)
      section.fetch(:roles).to_h do |name, body|
        [name.to_sym, build_role(name, body, archetypes, thresholds)]
      end
    end

    # Правила архетипа дополняются правилами самой роли: контракт может добавить
    # признак, не переписывая общий архетип и не мешая другим контрактам.
    # @param name [Symbol] имя роли, оно же имя метода контракта
    # @param body [Hash] описание роли: title, archetype, traits и, если нужно, rules/veto
    # @param archetypes [Hash]
    # @param thresholds [Hash]
    # @return [Settings::Role]
    def build_role(name, body, archetypes, thresholds)
      archetype = archetype_for(name, body, archetypes)
      Settings::Role.new(
        name: name, title: body.fetch(:title), traits: traits(name, body),
        rules: rules(archetype[:rules], body[:rules]),
        veto: rules(archetype[:veto], body[:veto]),
        threshold: thresholds.fetch(name, thresholds.fetch(:default))
      )
    end

    # @param name [Symbol]
    # @param body [Hash]
    # @param archetypes [Hash]
    # @return [Hash] архетип операции
    # @raise [ArgumentError] роль ссылается на архетип, которого нет в base.yml
    def archetype_for(name, body, archetypes)
      key = body.fetch(:archetype).to_sym
      archetypes.fetch(key) do
        raise ArgumentError, "роль #{name}: неизвестный архетип #{key}. " \
                             "Известны: #{archetypes.keys.join(", ")}"
      end
    end

    # @param groups [Array<Array<Hash>, nil>] правила архетипа и правила роли
    # @return [Array<Rule>]
    def rules(*groups)
      groups.flatten.compact.map { |entry| Rule.new(**entry) }
    end

    # @param name [Symbol] имя роли
    # @param body [Hash] описание роли
    # @return [Array<Symbol>] признаки роли
    # @raise [ArgumentError] признак не из словаря
    def traits(name, body)
      values = symbols(Array(body[:traits]))
      unknown = values - Settings::Role::TRAITS
      return values if unknown.empty?

      raise ArgumentError, "роль #{name}: неизвестные признаки #{unknown.join(", ")}. " \
                           "Известны: #{Settings::Role::TRAITS.join(", ")}"
    end

    # На роли, создающей операцию, завязаны тело запроса, лимиты и авторизация, а
    # на принимающей webhook — весь разбор колбэка. Двух таких быть не может.
    # @param roles [Hash{Symbol => Settings::Role}]
    # @return [Hash{Symbol => Settings::Role}] те же роли
    # @raise [ArgumentError] признак назначен не тому числу ролей
    def check(roles)
      CARDINALITY.each do |trait, (allowed, expectation)|
        marked = roles.values.select { |role| role.trait?(trait) }.map(&:name)
        next if allowed.cover?(marked.size)

        raise ArgumentError, "признак #{trait}: его должна нести #{expectation}, " \
                             "а несут #{marked.size} (#{marked.join(", ")})"
      end
      roles
    end

    # @param values [Array<String, Symbol>]
    # @return [Array<Symbol>]
    def symbols(values) = values.map(&:to_sym)
  end
end
