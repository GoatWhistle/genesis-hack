# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Testing
      # Результат проверки: по записи на каждую проверку. На ход сборки не влияет.
      class Report
        # Проверка: роль, содержание, результат; detail — только у непройденных.
        Check = Struct.new(:role, :title, :ok, :detail, keyword_init: true) do
          # @return [Hash{String => Object}] запись для mapping.yml
          def to_h
            { "role" => role.to_s, "check" => title, "ok" => ok, "detail" => detail }.compact
          end

          # @return [String] строка для сводки командной строки
          def to_s = "#{ok ? "ок" : "нет"}  #{role}: #{title}#{detail && " — #{detail}"}"
        end

        attr_reader :checks, :notes

        # @param checks [Array<Check>] проверки в порядке выполнения
        # @param notes [Array<String>] причины, по которым проверки не выполнены
        def initialize(checks: [], notes: [])
          @checks = checks
          @notes = notes
        end

        # @return [Array<Check>] непройденные проверки
        def failed = checks.reject(&:ok)

        # @return [Array<Check>] пройденные проверки
        def passed = checks.select(&:ok)

        # @return [Boolean] все ли проверки пройдены
        def ok? = failed.empty?

        # @return [String] строка сводки: количество пройденных и непройденных проверок
        def summary
          return "проверять нечем: #{notes.join("; ")}" if checks.empty?

          "проверок: #{checks.size}, прошло: #{passed.size}, не прошло: #{failed.size}"
        end

        # @return [Hash{String => Object}] отчёт целиком; ключи строками для mapping.yml
        #   и ответа HTTP
        def to_h
          { "passed" => passed.size, "failed" => failed.size, "notes" => notes,
            "checks" => checks.map(&:to_h) }
        end
      end
    end
  end
end
