# frozen_string_literal: true

module Rsocket
  module Mock
    Response = Data.define(:status, :headers, :body)

    class ExampleGenerationError < Rsocket::Error; end

    PATTERN_FALLBACKS = ["", "0", "a", "test", "example", "00000000000000000000"].freeze
    PATTERN_CLASS_CHARACTERS = [
      [->(text) { text.start_with?("^") }, "a"],
      [->(text) { text.include?("\\d") || text.match?(/0-9/) }, "0"],
      [->(text) { text.match?(/A-Z/) }, "A"],
      [->(text) { text.include?("\\w") || text.match?(/a-z/i) }, "a"]
    ].freeze
    private_constant :PATTERN_FALLBACKS, :PATTERN_CLASS_CHARACTERS

    # Выбор ответа на запрос по разобранному описанию API.
    #
    # Ответ на один и тот же запрос всегда один и тот же: случайные данные
    # превратили бы проверку интеграции в лотерею. Поэтому из нескольких
    # примеров берём первый, а не любой, и ничего не выдумываем на ходу.
    class Responder
      Route = Data.define(:verb, :pattern, :operation)
      private_constant :Route

      def initialize(spec)
        @routes = spec.operations.map { |operation| route(operation) }
        @examples = ExampleBuilder.new
      end

      def call(method:, path:)
        clean_path = path.to_s.split("?", 2).first
        route = @routes.find do |candidate|
          candidate.verb == method.to_s.downcase.to_sym && candidate.pattern.match?(clean_path)
        end

        return response_for(route.operation) if route
        if path?(clean_path)
          return error(405, "method_not_allowed", "Метод не описан для этого пути")
        end

        error(404, "route_not_found", "Такого пути нет в описании API")
      end

      private

      def route(operation)
        Route.new(
          verb: operation.http_method.to_sym,
          pattern: compile_path(operation.path),
          operation: operation
        )
      end

      def compile_path(path)
        parts = path.split(/(\{[^}]+\})/).map do |part|
          part.match?(/\A\{[^}]+\}\z/) ? "[^/]+" : Regexp.escape(part)
        end
        Regexp.new("\\A#{parts.join}/?\\z")
      end

      def path?(path)
        @routes.any? { |route| route.pattern.match?(path) }
      end

      def response_for(operation)
        status, response = select_response(operation.responses)
        body = response_body(response)
        headers = @examples.headers(response&.headers || [])
        Response.new(status:, headers:, body:)
      end

      def select_response(responses)
        numeric = responses.filter_map do |code, response|
          integer = Integer(code, exception: false)
          [integer, response] if integer&.between?(100, 599)
        end
        selected = numeric.find { |code, _response| code.between?(200, 299) } || numeric.first
        selected || [200, responses.values.first]
      end

      def response_body(response)
        return @examples.object(response&.fields || []) unless response && !response.examples.empty?

        deep_copy(response.examples.values.first)
      end

      def deep_copy(value)
        case value
        when Hash then value.to_h { |key, item| [key, deep_copy(item)] }
        when Array then value.map { |item| deep_copy(item) }
        when String then value.dup
        else value
        end
      end

      def error(status, code, message)
        body = { "error" => { "code" => code, "message" => message } }
        Response.new(status:, headers: {}, body:)
      end
    end

    # Сбор значений по описанию поля, когда готового примера в описании нет.
    #
    # Значения нарочно скучные и постоянные: даты из начала века, адреса на
    # example.test, нули вместо сумм. Такой ответ ни с чем не спутаешь и в
    # настоящую платёжную систему случайно не отправишь.
    class ExampleBuilder
      FORMATS = {
        "date" => "2000-01-01",
        "date-time" => "2000-01-01T00:00:00Z",
        "email" => "user@example.test",
        "hostname" => "example.test",
        "ipv4" => "192.0.2.1",
        "uri" => "https://example.test/resource",
        "uuid" => "00000000-0000-4000-8000-000000000000"
      }.freeze

      def object(fields)
        fields.to_h { |field| [field.name, value(field)] }
      end

      def headers(fields)
        fields.to_h { |field| [field.name.to_s.downcase, value(field).to_s] }
      end

      def value(field)
        return copy(field.example) unless field.example.nil?
        return copy(field.enum.first) if field.enum&.any?
        return structured(field) if structured?(field)

        scalar(field)
      end

      private

      def scalar(field)
        case field.type
        when "integer" then number(field).to_i
        when "number" then number(field).to_f
        when "boolean" then false
        when "string" then string(field)
        end
      end

      def structured?(field)
        field.type == "object" || field.type == "array" || field.children.any?
      end

      def structured(field)
        return object(field.children) unless field.type == "array"

        field.item ? [value(field.item)] : []
      end

      def number(field)
        return field.minimum unless field.minimum.nil?
        return [0, field.maximum].min unless field.maximum.nil?

        0
      end

      def string(field)
        return PatternExample.new(field.pattern).call if field.pattern

        value = FORMATS.fetch(field.format, "example")
        field.max_length ? value.slice(0, field.max_length) : value
      end

      def copy(value)
        case value
        when Hash then value.to_h { |key, item| [key, copy(item)] }
        when Array then value.map { |item| copy(item) }
        when String then value.dup
        else value
        end
      end
    end

    # Подбор строки под pattern из описания поля.
    #
    # Разбираем не весь язык регулярных выражений, а тот кусок, которым в
    # описаниях API пользуются на деле: классы символов, группы, повторы. Что бы
    # ни собралось, результат проверяется самой же регуляркой — заведомо
    # неверный пример хуже честного отказа.
    class PatternExample
      def initialize(source)
        @source = source
        @index = 0
      end

      def call
        regexp = Regexp.new(@source)
        candidate = sequence
        return candidate if regexp.match?(candidate)

        fallback = PATTERN_FALLBACKS.find { |value| regexp.match?(value) }
        return fallback if fallback

        raise ExampleGenerationError, failure_message
      rescue RegexpError => e
        raise ExampleGenerationError, "Некорректный pattern #{@source.inspect}: #{e.message}"
      end

      private

      def sequence(stop: [])
        output = +""
        output << quantified(atom) until done? || stop.include?(current)
        output
      end

      def atom
        character = take
        case character
        when "^", "$" then ""
        when "\\" then escaped
        when "[" then character_class
        when "(" then group
        when "." then "a"
        else character
        end
      end

      def escaped
        { "d" => "0", "D" => "a", "w" => "a", "W" => "-", "s" => " ",
          "S" => "a", "A" => "", "z" => "", "Z" => "" }.fetch(take) { @source[@index - 1] }
      end

      def character_class
        content = +""
        content << take until done? || current == "]"
        take if current == "]"
        class_character(content)
      end

      def class_character(content)
        match = PATTERN_CLASS_CHARACTERS.find { |predicate, _value| predicate.call(content) }
        return match.last if match

        content.delete_prefix("\\")[0] || "a"
      end

      def group
        return assertion_group if %w[?= ?!].include?(@source[@index, 2])

        @index += 2 if @source[@index, 2] == "?:"
        value = sequence(stop: ["|", ")"])
        skip_group_remainder
        value
      end

      def assertion_group
        @index += 2
        sequence(stop: [")"])
        take if current == ")"
        ""
      end

      def skip_group_remainder
        depth = 0
        until done?
          character = take
          depth += 1 if character == "("
          next unless character == ")"
          break if depth.zero?

          depth -= 1
        end
      end

      def quantified(value)
        case current
        when "+" then take && value
        when "*", "?" then take && ""
        when "{" then value * repetition
        else value
        end
      end

      def repetition
        take
        digits = +""
        digits << take while current&.match?(/\d/)
        take until done? || current == "}"
        take if current == "}"
        digits.empty? ? 1 : digits.to_i
      end

      def current
        @source[@index]
      end

      def take
        character = current
        @index += 1
        character
      end

      def done?
        @index >= @source.length
      end

      def failure_message
        "Не удалось собрать строку, соответствующую pattern #{@source.inspect}"
      end
    end
  end
end
