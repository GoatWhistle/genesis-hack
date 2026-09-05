# frozen_string_literal: true

module Config
  # Одно правило классификации: по какому полю операции смотрим, какой регуляркой
  # и сколько очков даём за совпадение. Веса нужны, чтобы слабый признак (POST)
  # не перевешивал сильный (глагол в operationId).
  class Rule
    FIELDS = %w[method_name operation_id path http_method summary description tags].freeze

    attr_reader :field, :pattern, :weight

    # @param field [String, Symbol] поле кандидата из FIELDS
    # @param pattern [String] регулярка, компилируется без учёта регистра
    # @param weight [Integer] сколько очков даёт совпадение
    # @raise [ArgumentError] поле не из FIELDS
    def initialize(field:, pattern:, weight: 0)
      raise ArgumentError, "неизвестное поле правила: #{field}" unless FIELDS.include?(field.to_s)

      @field = field.to_s
      @pattern = Regexp.new(pattern, Regexp::IGNORECASE)
      @weight = weight.to_i
    end

    # Совпало ли правило с текстом соответствующего поля.
    # @param subject [Models::ApiOperation] кандидат на роль
    # @return [Boolean] nil в поле считается несовпадением
    def matches?(subject)
      value = subject.public_send(field)
      return false if value.nil?

      pattern.match?(Array(value).join(" "))
    end

    # @return [String] правило словами — уходит в mapping.yml
    def to_s
      "#{field} =~ /#{pattern.source}/"
    end
  end
end
