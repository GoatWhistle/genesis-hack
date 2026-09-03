# frozen_string_literal: true

require "fileutils"
require "open3"
require "tempfile"
require "tmpdir"
require "yaml"

require "rsocket/cli"

# Командную строку проверяем запуском настоящего процесса: только так видно
# и код возврата, и то, что человек читает на экране.
#
# Обе точки входа живут в одном файле: с точки зрения проверки это одна
# командная строка с двумя дверями.
# rubocop:disable-next RSpec/SpecFilePathFormat
RSpec.describe Rsocket::CLI do
  # Берём первое попавшееся описание из examples/: конкретный провайдер тестам
  # неинтересен, важно только что файл настоящий и разбирается.
  let(:sample_spec) do
    Dir[File.join(Rsocket.root, Rsocket::Doctor::SAMPLE_SPEC_GLOB)].min
  end

  # Битое описание делаем сами: на заведомо целом файле разбор не проверить.
  let(:broken_spec) do
    file = Tempfile.new(["broken", ".yaml"])
    file.write("openapi: 3.0.0\npaths:\n  - [не закрытая скобка\n")
    file.close
    file.path
  end

  # Результаты разбора пишутся во временный каталог: тесты не должны трогать
  # output/ в репозитории.
  let(:out_dir) { Dir.mktmpdir("rsocket-cli") }

  after { FileUtils.rm_rf(out_dir) }

  # Правка человека: первой роли назначается операция второй — так проверяется
  # именно уважение к правке, а не обработка опечатки.
  def edit_manifest
    path = File.join(out_dir, Rsocket::CLI::MANIFEST_NAME)
    document = YAML.safe_load_file(path)
    first, second = document["roles"].keys.first(2)
    document["roles"][first]["operation"] = document["roles"][second]["operation"]
    File.write(path, YAML.dump(document))
  end

  # Возвращает [вывод, код возврата]. Потоки склеены: пользователь видит их
  # вместе, значит и проверять их нужно вместе.
  def run(binary, *args)
    out, err, status = Open3.capture3(RbConfig.ruby, File.join(Rsocket.root, "bin", binary),
                                      *args, chdir: Rsocket.root)
    [out + err, status.exitstatus]
  end

  # След вызовов в выводе означает, что мы уронили ожидаемый отказ как баг.
  def backtrace?(text)
    text.match?(/\.rb:\d+:in /) || text.include?("backtrace")
  end

  describe "version" do
    it "печатает версию инструмента", :aggregate_failures do
      output, code = run("rsocket", "version")

      expect(output).to include(Rsocket::VERSION)
      expect(code).to eq(0)
    end
  end

  describe "doctor" do
    it "проходит на текущем состоянии репозитория", :aggregate_failures do
      output, code = run("rsocket", "doctor")

      expect(output).to include("Всё на месте")
      expect(output).not_to include("[плохо]")
      expect(code).to eq(0)
    end

    it "отчитывается по каждому пункту отдельной строкой", :aggregate_failures do
      output, = run("rsocket", "doctor")

      expect(output).to include("Ruby #{RUBY_VERSION}", "Gemfile.lock", "каталоги проекта")
      expect(output).to include("описания API", "output/")
    end

    it "смотрит на настоящие каталоги, а не на выдуманные" do
      missing = Rsocket::Doctor::REQUIRED_DIRS
                .reject { |dir| Dir.exist?(File.join(Rsocket.root, dir)) }

      expect(missing).to be_empty
    end
  end

  describe "analyze" do
    it "объясняет, что файла описания нет, и уходит с ненулевым кодом", :aggregate_failures do
      output, code = run("rsocket", "analyze", "--spec", File.join(Rsocket.root, "нет-файла.yaml"))

      expect(output).to include("не найден")
      expect(code).to eq(1)
      expect(backtrace?(output)).to be(false)
    end

    it "объясняет, что описание не разбирается как YAML", :aggregate_failures do
      output, code = run("rsocket", "analyze", "--spec", broken_spec)

      expect(output).to include("YAML")
      expect(code).to eq(1)
      expect(backtrace?(output)).to be(false)
    end

    it "печатает отчёт о разборе и уходит с нулевым кодом", :aggregate_failures do
      output, code = run("rsocket", "analyze", "--spec", sample_spec, "--out", out_dir)

      expect(output).to include("Понято уверенно", "Требует подтверждения", "Не поддержано")
      expect(code).to eq(0)
    end

    it "пишет файл догадок в указанный каталог", :aggregate_failures do
      run("rsocket", "analyze", "--spec", sample_spec, "--out", out_dir)
      written = File.read(File.join(out_dir, described_class::MANIFEST_NAME))

      expect(written).to include("roles:", "statuses:", "money:")
      expect(written).to start_with("# Что RSOCKET понял")
    end

    # Прогон на месте прошлого не должен переубеждать человека: если он поправил
    # роль, следующий запуск обязан её сохранить.
    it "уважает правку человека в файле догадок" do
      run("rsocket", "analyze", "--spec", sample_spec, "--out", out_dir)
      edit_manifest
      output, = run("rsocket", "analyze", "--spec", sample_spec, "--out", out_dir)

      expect(output).to include("задана человеком")
    end

    it "разбирает все описания из examples/", :aggregate_failures do
      Dir[File.join(Rsocket.root, Rsocket::Doctor::SAMPLE_SPEC_GLOB)].each do |path|
        output, code = run("rsocket", "analyze", "--spec", path, "--out", out_dir)

        expect(code).to eq(0), "не разобралось: #{path}"
        expect(output).to include("Понято уверенно")
      end
    end

    it "требует --spec", :aggregate_failures do
      output, code = run("rsocket", "analyze")

      expect(output).to include("spec")
      expect(code).not_to eq(0)
      expect(backtrace?(output)).to be(false)
    end
  end

  describe "mock и verify" do
    it "оставляет verify явно несобранным", :aggregate_failures do
      output, code = run("rsocket", "verify", "--spec", sample_spec)

      expect(output).to include("ещё не собрана")
      expect(code).to eq(described_class::STAGE_NOT_READY)
    end

    it "запускает mock на выбранном порту" do
      server = instance_double(Rsocket::Mock::Server, start: nil)
      allow(Rsocket::Mock::Server).to receive(:new).and_return(server)

      described_class.start(["mock", "--spec", sample_spec, "--port", "4123"])

      expect(server).to have_received(:start).with(port: 4123)
    end

    it "не принимают порт вне допустимого диапазона", :aggregate_failures do
      output, code = run("rsocket", "mock", "--spec", sample_spec, "--port", "99999")

      expect(output).to include("порт")
      expect(code).to eq(1)
      expect(backtrace?(output)).to be(false)
    end
  end

  describe "точка входа integrate" do
    it "печатает справку по --help", :aggregate_failures do
      output, code = run("integrate", "--help")

      expect(output).to include("--spec", "--provider", "--lang")
      expect(code).to eq(0)
    end

    it "отказывается собирать интеграцию на другом языке", :aggregate_failures do
      output, code = run("integrate", "--spec", sample_spec, "--provider", "любой", "--lang", "go")

      expect(output).to include("не поддерживается")
      expect(code).to eq(1)
    end

    it "требует --provider", :aggregate_failures do
      output, code = run("integrate", "--spec", sample_spec)

      expect(output).to include("provider")
      expect(code).to eq(1)
    end

    it "доходит до честного сообщения о несобранной стадии", :aggregate_failures do
      output, code = run("integrate", "--spec", sample_spec, "--provider", "любой")

      expect(output).to include("ещё не собрана")
      expect(code).to eq(described_class::STAGE_NOT_READY)
    end

    it "объясняет, что файла описания нет", :aggregate_failures do
      output, code = run("integrate", "--spec", "нет-файла.yaml", "--provider", "любой")

      expect(output).to include("не найден")
      expect(code).to eq(1)
      expect(backtrace?(output)).to be(false)
    end
  end
end
