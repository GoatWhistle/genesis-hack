# frozen_string_literal: true

require "date"
require "thor"
require "yaml"

require_relative "../rsocket"

module Rsocket
  # Командная строка инструмента.
  #
  # Часть конвейера ещё не собрана. Команды несобранных стадий не притворяются,
  # что что-то сделали: они честно проверяют аргументы и уходят с кодом 2 —
  # спутать это с успехом нельзя ни глазами, ни скриптом.
  class CLI < Thor
    # Код возврата для стадии, которая ещё не собрана. Отдельный от 1, чтобы
    # «не готово» не путалось с «сломано».
    STAGE_NOT_READY = 2

    def self.exit_on_failure?
      true
    end

    # Ожидаемые отказы печатаются человеку одной строкой. След вызовов здесь
    # только мешает: это не наш баг, а неверный ввод или неготовое окружение.
    # Всё остальное уходит наверх как есть — такое чинить нам.
    def self.start(given_args = ARGV, config = {})
      super
    rescue Rsocket::Error => e
      warn "Ошибка: #{e.message}"
      exit 1
    end

    # Чтение входного файла нужно и командам Thor, и плоскому bin/integrate,
    # поэтому живёт на уровне класса.
    def self.read_spec(path)
      raise Rsocket::SpecError, "не указан путь к описанию API" if path.nil? || path.empty?
      raise Rsocket::SpecError, "файл описания не найден: #{path}" unless File.file?(path)
      raise Rsocket::SpecError, "файл описания не читается: #{path}" unless File.readable?(path)

      parse_yaml(File.read(path), path)
    rescue SystemCallError => e
      raise Rsocket::SpecError, "файл описания не прочитать: #{path} (#{e.class})"
    end

    def self.parse_yaml(text, path)
      document = YAML.safe_load(text, aliases: true, permitted_classes: [Date, Time])
      raise Rsocket::SpecError.new("описание пустое", where: path) if document.nil?
      raise Rsocket::SpecError.new("в корне описания ожидается набор полей", where: path) unless
        document.is_a?(Hash)

      document
    rescue Psych::SyntaxError => e
      raise Rsocket::SpecError.new("описание не разбирается как YAML: #{e.problem}",
                                   where: "#{path}, строка #{e.line}")
    end
    private_class_method :parse_yaml

    desc "version", "Показать версию инструмента"
    def version
      say "rsocket #{Rsocket::VERSION}"
    end

    desc "doctor", "Проверить, что окружение готово к работе"
    def doctor
      checks = Doctor.new.checks
      checks.each { |check| say "#{check.ok ? "[ ок ]" : "[плохо]"} #{check.title}" }
      say ""
      broken = checks.reject(&:ok)
      broken.empty? ? say("Всё на месте — можно работать.") : say_broken(broken)
      exit(broken.empty? ? 0 : 1)
    end

    desc "analyze", "Разобрать описание API и сложить догадки в файл"
    method_option :spec, type: :string, required: true, desc: "Путь к описанию API (OpenAPI)"
    method_option :out, type: :string, default: "output", desc: "Каталог для результатов разбора"
    def analyze
      spec_ready(options[:spec])
      stage_not_ready("разбор описания", "T1.1-T1.8")
    end

    desc "mock", "Поднять поддельный сервер провайдера по описанию"
    method_option :spec, type: :string, required: true, desc: "Путь к описанию API (OpenAPI)"
    method_option :port, type: :numeric, default: 4010, desc: "Порт поддельного сервера"
    def mock
      port = options[:port].to_i
      unless (1..65_535).cover?(port)
        raise Rsocket::Error, "порт вне допустимого диапазона: #{port}"
      end

      spec_ready(options[:spec])
      stage_not_ready("поддельный сервер", "T3.1")
    end

    desc "verify", "Проверить готовую интеграцию против поддельного сервера"
    method_option :spec, type: :string, required: true, desc: "Путь к описанию API (OpenAPI)"
    method_option :out, type: :string, default: "output", desc: "Каталог с готовой интеграцией"
    def verify
      spec_ready(options[:spec])
      stage_not_ready("проверка интеграции", "T3.3")
    end

    private

    # Единственное, что заготовка команды умеет по-настоящему: убедиться, что
    # ей дали читаемое описание. Об этом и сообщаем.
    def spec_ready(path)
      self.class.read_spec(path)
      say "Описание прочитано и разбирается как YAML: #{path}"
    end

    def stage_not_ready(stage, tasks)
      say "Стадия «#{stage}» ещё не собрана (задачи #{tasks})."
      say "Результатов нет, и выдумывать их нечего."
      exit STAGE_NOT_READY
    end

    def say_broken(broken)
      say "Чинить (#{broken.size}):"
      broken.each { |check| say "  - #{check.title}: #{check.hint}" }
    end
  end

  # Проверка окружения для команды doctor.
  #
  # Каждая проверка делается делом, а не верой: версия читается из файла,
  # каталоги ищутся на диске, описание разбирается разборщиком, право на
  # запись подтверждается записью.
  class Doctor
    # Где лежат примеры описаний API. Имён провайдеров здесь нет намеренно:
    # doctor проверяет всё, что лежит в examples/, и продолжит работать, когда
    # примеров станет больше.
    SAMPLE_SPEC_GLOB = "examples/*/provider_api.yaml"

    # Каталоги, без которых конвейеру негде жить.
    REQUIRED_DIRS = %w[
      lib/rsocket/spec lib/rsocket/ir lib/rsocket/classify lib/rsocket/dictionaries
      lib/rsocket/manifest lib/rsocket/generate lib/rsocket/templates lib/rsocket/runtime
      lib/rsocket/mock lib/rsocket/verify lib/rsocket/report
      reference examples output
    ].freeze

    # Строка отчёта: что проверяли, вышло ли, и что делать, если нет.
    Check = Struct.new(:title, :ok, :hint)

    def checks
      [
        ruby_check, gems_check, dirs_check, specs_check,
        attempt("каталог output/ доступен на запись") { write_probe }
      ]
    end

    private

    # Если попытка прошла молча — всё хорошо; если упала — человеку
    # показывается ровно то, обо что споткнулись.
    def attempt(title)
      yield
      Check.new(title, true, nil)
    rescue Rsocket::Error, SystemCallError => e
      Check.new(title, false, e.message)
    end

    # Читаем все примеры, какие лежат, а не первый попавшийся: битым может
    # оказаться тот, который кто-то только что добавил.
    def specs_check
      title = "описания API в examples/ читаются"
      paths = Dir[File.join(Rsocket.root, SAMPLE_SPEC_GLOB)]
      return Check.new(title, false, "нет ни одного файла provider_api.yaml") if paths.empty?

      paths.each { |path| CLI.read_spec(path) }
      Check.new("#{title} (#{paths.length})", true, nil)
    rescue Rsocket::Error => e
      Check.new(title, false, e.message)
    end

    # Право на запись проверяем записью: разрешения в файловой системе врут
    # чаще, чем попытка создать файл.
    def write_probe
      probe = File.join(Rsocket.root, "output", ".rsocket-doctor-#{Process.pid}")
      File.write(probe, "")
      File.delete(probe)
    end

    def ruby_check
      want = File.read(File.join(Rsocket.root, ".ruby-version")).strip
      Check.new("Ruby #{RUBY_VERSION}, в .ruby-version записана #{want}", want == RUBY_VERSION,
                "переключитесь: rbenv install #{want} && rbenv local #{want}")
    rescue SystemCallError
      Check.new("версия Ruby", false, "в корне репозитория нет файла .ruby-version")
    end

    # bundler проверяем попыткой загрузить, а не верой в переменные среды.
    def gems_check
      require "bundler"
      lock = File.file?(File.join(Rsocket.root, "Gemfile.lock"))
      Check.new("bundler #{Bundler::VERSION} и Gemfile.lock на месте", lock,
                "поставьте гемы: bundle install")
    rescue LoadError
      Check.new("bundler доступен", false, "поставьте bundler: gem install bundler")
    end

    def dirs_check
      missing = REQUIRED_DIRS.reject { |dir| Dir.exist?(File.join(Rsocket.root, dir)) }
      Check.new("каталоги проекта на месте (#{REQUIRED_DIRS.size})", missing.empty?,
                "не хватает: #{missing.join(", ")}")
    end
  end
end
