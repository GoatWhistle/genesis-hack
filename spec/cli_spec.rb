# frozen_string_literal: true

require "open3"
require "tempfile"

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

    it "не молчит про несобранную стадию, когда аргументы в порядке", :aggregate_failures do
      output, code = run("rsocket", "analyze", "--spec", sample_spec)

      expect(output).to include("ещё не собрана", "T1.1-T1.8")
      expect(code).to eq(described_class::STAGE_NOT_READY)
    end

    it "требует --spec", :aggregate_failures do
      output, code = run("rsocket", "analyze")

      expect(output).to include("spec")
      expect(code).not_to eq(0)
      expect(backtrace?(output)).to be(false)
    end
  end

  describe "mock и verify" do
    it "проверяют аргументы и честно сообщают о несобранной стадии", :aggregate_failures do
      %w[mock verify].each do |command|
        output, code = run("rsocket", command, "--spec", sample_spec)

        expect(output).to include("ещё не собрана")
        expect(code).to eq(described_class::STAGE_NOT_READY)
      end
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
