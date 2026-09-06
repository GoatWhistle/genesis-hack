# frozen_string_literal: true

module Config
  # Правило классификации: поле операции, регулярка и очки за совпадение.
  class Rule
    # incoming — направление, объявленное самим описанием: операция из раздела
    # webhooks приходит к нам, а не уходит от нас. Значение булево, поэтому
    # регулярка правила сравнивается со словом true.
    FIELDS = %w[method_name operation_id path http_method summary description tags
                incoming].freeze

    attr_reader :field, :pattern, :weight, :except

    # @param field [String, Symbol] поле кандидата из FIELDS
    # @param pattern [String] регулярка, компилируется без учёта регистра
    # @param weight [Integer] сколько очков даёт совпадение
    # @param except [Array<Hash>] оговорки вида { field:, pattern: }: если совпала
    #   хоть одна, правило не срабатывает. Нужны там, где смысл задаёт пара полей:
    #   POST статуса не даёт, если в имени и адресе не сказано, что это чтение
    # @raise [ArgumentError] поле не из FIELDS
    def initialize(field:, pattern:, weight: 0, except: [])
      raise ArgumentError, "неизвестное поле правила: #{field}" unless FIELDS.include?(field.to_s)

      @field = field.to_s
      @pattern = Regexp.new(pattern, Regexp::IGNORECASE)
      @weight = weight.to_i
      @except = Array(except).map { |entry| Rule.new(**entry) }
    end

    # Совпадение правила с текстом соответствующего поля.
    # @param subject [Models::ApiOperation] кандидат на роль
    # @return [Boolean] nil в поле считается несовпадением
    def matches?(subject)
      return false if except.any? { |rule| rule.matches?(subject) }

      value = subject.public_send(field)
      return false if value.nil?

      pattern.match?(Array(value).join(" "))
    end

    # @return [String] текстовое представление правила для mapping.yml
    def to_s
      return "#{field} =~ /#{pattern.source}/" if except.empty?

      "#{field} =~ /#{pattern.source}/ кроме #{except.join(", ")}"
    end
  end
end
