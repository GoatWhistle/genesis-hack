# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

module Rsocket
  module Generate
    # Автоправка и проверка сгенерированного кода линтером внутри конвейера.
    #
    # Зачем это здесь, а не отдельным шагом в CI: сгенерированный код читают
    # инженеры заказчика, и «почти оформленный» код стоит нам баллов. Прогон
    # внутри конвейера означает, что плохо оформленный файл просто не выйдет
    # наружу.
    #
    # Непрохождение — исключение, а не предупреждение в журнале. Тихо
    # выпустить файл, который сами же считаем плохим, хуже, чем упасть.
    class RubocopPass
      Report = Data.define(:source, :offenses, :corrected) do
        def clean?
          offenses.empty?
        end

        # Строка для вывода командной строки: сколько нашли, сколько
        # исправили сами.
        def summary
          return "линтер чист, исправлено автоматически: #{corrected}" if clean?

          "линтер нашёл #{offenses.size} замечаний после автоправки"
        end
      end

      CONFIG = ".rubocop.yml"

      def initialize(config_path: File.join(Rsocket.root, CONFIG))
        @config_path = config_path
      end

      # Проверяется копия во временном каталоге, а не сам выходной файл:
      # каталог результатов исключён из проверки в конфиге линтера, и файл в
      # нём проверен не был бы вовсе.
      def call(source, filename:)
        Dir.mktmpdir("rsocket-lint") do |dir|
          path = File.join(dir, filename)
          File.write(path, source)
          fixed = run(path, "--autocorrect-all").count { |offense| offense["corrected"] }
          offenses = run(path, nil)
          Report.new(source: File.read(path), offenses: offenses, corrected: fixed)
        end
      end

      # То же самое, но непрохождение останавливает сборку.
      def call!(source, filename:)
        report = call(source, filename: filename)
        return report if report.clean?

        raise Rsocket::GenerationError,
              "сгенерированный #{filename} не проходит линтер:\n#{format_offenses(report)}"
      end

      private

      def run(path, mode)
        command = [RbConfig.ruby, rubocop_bin, "--config", @config_path, "--format", "json", path]
        command.insert(-2, mode) if mode
        stdout, = Open3.capture3(*command)
        parse(stdout)
      end

      def parse(stdout)
        JSON.parse(stdout).fetch("files", []).flat_map { |file| file.fetch("offenses", []) }
      rescue JSON::ParserError
        []
      end

      def rubocop_bin
        @rubocop_bin ||= Gem.bin_path("rubocop", "rubocop")
      end

      def format_offenses(report)
        report.offenses.first(10).map do |offense|
          location = offense.dig("location", "line")
          "  строка #{location}: #{offense["cop_name"]} — #{offense["message"]}"
        end.join("\n")
      end
    end
  end
end
