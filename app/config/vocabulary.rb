# frozen_string_literal: true

module Config
  # Словарь контракта: распознавание из base.yml, имена и выражения из профиля.
  class Vocabulary
    # @param base [Hash] разобранный base.yml
    # @param contract [Hash] разобранный contract.yml профиля
    def initialize(base, contract)
      @base = base
      @contract = contract
    end

    # @return [Hash] секции статусов, ошибок и ограничений для Settings
    def mappings
      { status_mapping: statuses, error_mapping: errors, constraints: constraints }
    end

    # @return [Hash] словари полей, заголовков, предпроверок и авторизации
    def dictionaries
      sources = @contract.fetch(:sources)
      fields(sources).merge(
        callback_fields: patterns_hash(@base.fetch(:callback_fields)),
        headers: patterns_hash(@base.fetch(:headers)),
        header_sources: sources.fetch(:headers),
        conditions: @contract.fetch(:conditions) || {},
        auth_templates: @contract.fetch(:authorization)
      )
    end

    private

    # @param sources [Hash] выражения контракта по имени поля
    # @return [Hash] словари тела запроса, реквизитов получателя и параметров пути
    def fields(sources)
      {
        payload_fields: dictionary(:payload_patterns, sources.fetch(:payload)),
        requisite_fields: dictionary(:requisite_patterns, sources.fetch(:requisite)),
        path_params: dictionary(:path_patterns, sources.fetch(:path))
      }
    end

    # Контракт ссылается на группу состояний из base.yml либо задаёт свои шаблоны.
    # @return [Hash{Symbol => Array<Regexp>}] статус контракта → чем его узнать
    def statuses
      groups = @base.fetch(:status_patterns)
      @contract.fetch(:statuses).transform_values do |value|
        compile(value.is_a?(Array) ? value : groups.fetch(value.to_sym))
      end
    end

    # Связь идёт через смысл ошибки: код ответа → смысл → запись контракта.
    # @return [Hash] { codes: { "429" => {...} }, default: {...} }
    def errors
      section = @contract.fetch(:errors)
      semantics = section.fetch(:semantics)
      codes = @base.fetch(:error_semantics).to_h do |code, meaning|
        [code.to_s, semantics.fetch(meaning.to_sym)]
      end
      { codes: codes, default: section.fetch(:default) }
    end

    # @return [Hash] единицы суммы, шаблоны её печати и правила поиска границ в тексте
    def constraints
      units = @base.fetch(:amount_units)
      {
        minor_patterns: compile(units.fetch(:minor_patterns)),
        multiplier: units.fetch(:multiplier),
        minor_requires_integer: units.fetch(:minor_requires_integer, true),
        rendering: @contract.fetch(:amount),
        text_rules: text_rules
      }
    end

    # @return [Array<Hash>] правила поиска границ со скомпилированной регуляркой
    def text_rules
      @base.fetch(:amount_text_rules).map do |rule|
        rule.merge(pattern: compile_one(rule.fetch(:pattern)), kind: rule.fetch(:kind).to_sym)
      end
    end

    # Имя и регулярки — из base.yml, выражение — из контракта; первое совпадение.
    # @param section [Symbol] имя секции base.yml
    # @param sources [Hash{Symbol => String}] поле контракта → выражение на Ruby
    # @return [Array<Hash>] записи { field:, patterns:, source: }
    def dictionary(section, sources)
      @base.fetch(section).map do |entry|
        entry.merge(patterns: compile(entry.fetch(:patterns)),
                    source: sources[entry.fetch(:field).to_sym])
      end
    end

    # @param raw [Hash{Symbol => Array<String>}]
    # @return [Hash{Symbol => Array<Regexp>}]
    def patterns_hash(raw)
      raw.transform_values { |patterns| compile(patterns) }
    end

    # @param patterns [String, Array<String>]
    # @return [Array<Regexp>]
    def compile(patterns)
      Array(patterns).map { |pattern| compile_one(pattern) }
    end

    # @param pattern [String]
    # @return [Regexp] без учёта регистра: часть провайдеров пишет статусы в верхнем регистре
    def compile_one(pattern)
      Regexp.new(pattern, Regexp::IGNORECASE)
    end
  end
end
