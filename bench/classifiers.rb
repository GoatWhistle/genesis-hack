# frozen_string_literal: true

# Замер трёх способов раздачи ролей на описаниях из examples/. Считает три вещи:
# сколько ролей размечено верно, сколько занимает сама разметка и во что обходится
# поход наружу.
#
# Правила гоняются десятками прогонов — они быстрые и бесплатные. Сетевые способы
# прогоняются по нескольку раз, и между запросами выдерживается пауза: бесплатный
# тариф Voyage считает запросы штуками в минуту, и без паузы замерялось бы
# ожидание лимита, а не работа модели.
#
#   bundle exec ruby bench/classifiers.rb                    # все три
#   bundle exec ruby bench/classifiers.rb rules embeddings   # только эти
#   BENCH_RUNS=5 BENCH_PAUSE=21 bundle exec ruby bench/classifiers.rb
#
# Итог печатается таблицами и, если задан BENCH_JSON, складывается файлом.

require_relative "../app/boot"
require "json"

module Bench
  # Где лежат описания. Первые четыре — те, на которых правила и писались, и мерить
  # только на них нечестно: словарь base.yml подгонялся ровно под них. Пятое лежит
  # отдельно и правилам незнакомо — там те же четыре операции названы словами,
  # которых в словаре нет.
  SPECS = {
    "novapay" => "examples/novapay/provider_api.yaml",
    "swiftpay" => "examples/swiftpay/provider_api.yaml",
    "kassabox" => "examples/kassabox/provider_api.yaml",
    "nordbank" => "examples/nordbank/provider_api.yaml",
    "quantumpay" => "bench/unseen/provider_api.yaml"
  }.freeze

  # Описания, на которых правила настраивались: по ним меряется остальной конвейер.
  TUNED = %w[novapay swiftpay kassabox nordbank].freeze

  # Верная разметка. Для examples/ — та же, что проверяют юнит-тесты классификатора
  # на правилах: три описания из четырёх webhook не объявляют, и правильный ответ
  # там — пустая роль.
  TRUTH = {
    "novapay" => { create_request: "create_payout", fetch_status: "get_payout_status",
                   process_callback: "payout_webhook", cancel_request: "cancel_payout" },
    "swiftpay" => { create_request: "submit_transfer", fetch_status: "fetch_transfer",
                    process_callback: nil, cancel_request: "revoke_transfer" },
    "kassabox" => { create_request: "make_transfer", fetch_status: "transfer_info",
                    process_callback: nil, cancel_request: "abort_transfer" },
    "nordbank" => { create_request: "create_payment_order", fetch_status: "get_payment_order",
                    process_callback: nil, cancel_request: "revoke_payment_order" },
    "quantumpay" => { create_request: "enqueue_disbursement",
                      fetch_status: "disbursement_snapshot",
                      process_callback: "disbursement_signal",
                      cancel_request: "halt_disbursement" }
  }.freeze

  # Цены за миллион токенов, чтобы счёт был в деньгах, а не в штуках. Чтение из
  # кэша считается отдельно: оно стоит десятую часть обычного входного токена, а
  # у запроса через прокси кэш составляет большую часть входа.
  PRICES = {
    "claude-opus-5" => { input: 5.0, output: 25.0, cached: 0.5 },
    "voyage-3.5-lite" => { input: 0.02, output: 0.0, cached: 0.0 }
  }.freeze

  # Сколько прогонов на способ по умолчанию: правила ничего не стоят, сетевые
  # способы стоят денег и времени.
  RUNS = { "rules" => 50, "embeddings" => 3, "llm" => 3 }.freeze

  # Пауза перед запросом, секунды. У каждого сервиса своя: бесплатный тариф Voyage
  # разрешает три запроса в минуту, и без паузы замерялось бы ожидание лимита.
  PAUSES = { "rules" => 0.0, "embeddings" => 21.0, "llm" => 1.0 }.freeze

  # Один прогон одного способа на одном описании.
  Measurement = Struct.new(:kind, :provider, :seconds, :correct, :mistakes, keyword_init: true)

  # Счётчик расхода: оборачивает клиент Claude и запоминает, во что обошёлся
  # каждый запрос. В самом классификаторе этого нет намеренно — считать деньги
  # нужно замеру, а не сборке.
  class Meter
    attr_reader :input, :output, :cached, :calls

    # @param client [Anthropic::Client]
    def initialize(client)
      @client = client
      @input = @output = @cached = @calls = 0
    end

    # @return [Meter] клиент адресуется как client.messages.create
    def messages = self

    # @return [Anthropic::Message]
    def create(**)
      message = @client.messages.create(**)
      record(message.usage)
      message
    end

    private

    # @param usage [Anthropic::Usage]
    # @return [void]
    def record(usage)
      @calls += 1
      @input += usage.input_tokens.to_i
      @output += usage.output_tokens.to_i
      @cached += usage.cache_read_input_tokens.to_i
    end
  end

  # То же для векторизатора. Voyage считает токены сам, но клиент их не отдаёт,
  # поэтому здесь считаются символы — для порядка величины этого хватает.
  class Counter
    CHARS_PER_TOKEN = 3.5

    attr_reader :calls, :characters

    # @param embedder [Service::AdapterBuilder::Ports::Embedder]
    def initialize(embedder)
      @embedder = embedder
      @calls = @characters = 0
    end

    # @return [Array<Array<Float>>]
    def embed(texts)
      @calls += 1
      @characters += texts.sum(&:length)
      @embedder.embed(texts)
    end

    # @return [Integer] оценка расхода токенов
    def tokens = (@characters / CHARS_PER_TOKEN).round

    # @return [String]
    def to_s = @embedder.to_s
  end

  # Прогон замера: каждый способ на каждом описании по нескольку раз.
  class Suite
    attr_reader :measurements, :meters

    # @param kinds [Array<String>] какие способы мерить
    # @param runs [Hash{String => Integer}] сколько прогонов на способ
    # @param pauses [Hash{String => Float}] пауза перед запросом, по способам
    def initialize(kinds:, providers: TRUTH.keys, runs: RUNS, pauses: PAUSES)
      @kinds = kinds
      @providers = providers
      @runs = runs
      @pauses = pauses
      @rules = Config::Importer.call
      @operations = @providers.to_h { |provider| [provider, operations_of(provider)] }
      @measurements = []
      @meters = {}
    end

    # @return [Array<Measurement>]
    def call
      @kinds.each { |kind| measure(kind) }
      @measurements
    end

    # Время всего остального конвейера: разбор описания, решения и печать. Замер
    # ставит его рядом с разметкой, иначе разница в секундах повисает в воздухе.
    # @return [Float] секунды на одну сборку без раздачи ролей
    def pipeline_without_classification
      whole = TUNED.sum { |provider| timed { build(provider) }.first } / TUNED.size
      whole - median_of("rules")
    end

    # @param kind [String]
    # @return [Float] медиана секунд
    def median_of(kind)
      median(@measurements.select { |item| item.kind == kind }.map(&:seconds))
    end

    private

    # @param kind [String]
    # @return [void]
    def measure(kind)
      classifier = build_classifier(kind)
      @runs.fetch(kind).times do
        @providers.each { |provider| @measurements << once(kind, classifier, provider) }
      end
    end

    # @return [Measurement]
    def once(kind, classifier, provider)
      operations = @operations.fetch(provider)
      sleep(@pauses.fetch(kind, 0.0))
      seconds, bindings = timed { classifier.call(operations) }
      mistakes = mistakes_in(provider, bindings)
      Measurement.new(kind: kind, provider: provider, seconds: seconds,
                      correct: TRUTH.fetch(provider).size - mistakes.size, mistakes: mistakes)
    end

    # @return [Array<String>] роли, размеченные не так, как в TRUTH
    def mistakes_in(provider, bindings)
      TRUTH.fetch(provider).filter_map do |role, expected|
        got = bindings.fetch(role).operation&.method_name
        next if got == expected

        "#{role}: #{got || "заглушка"} вместо #{expected || "заглушки"}"
      end
    end

    # @return [Array(Float, Object)] секунды и то, что вернул блок
    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      value = yield
      [Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, value]
    end

    # Счётчики расхода надеваются здесь: классификатору о них знать незачем.
    # @param kind [String]
    # @return [Service::AdapterBuilder::Ports::Classifier]
    def build_classifier(kind)
      case kind
      when "llm" then with_meter(kind, Meter.new(Anthropic::Client.new)) do |meter|
        Adapter::Classification::Llm.new(@rules, client: meter)
      end
      when "embeddings" then with_meter(kind, Counter.new(Adapter::Embedding::Voyage.new)) do |c|
        Adapter::Classification::Embeddings.new(@rules, embedder: c)
      end
      else Rsocket.classifier(kind, @rules)
      end
    end

    # @return [Object] классификатор, собранный вокруг счётчика
    def with_meter(kind, meter)
      @meters[kind] = meter
      yield(meter)
    end

    # @param provider [String]
    # @return [Array<Models::ApiOperation>]
    def operations_of(provider)
      document = Adapter::Loader::File::SpecLoader.new.read(spec_of(provider))
      Service::AdapterBuilder::Parsing::SpecParser.new(document).call.operations
    end

    # @param provider [String]
    # @return [Service::AdapterBuilder::Builder::Result]
    def build(provider)
      Rsocket.builder(rules: @rules).call(reference: spec_of(provider), provider: provider)
    end

    # @param provider [String]
    # @return [String]
    def spec_of(provider) = Rsocket::ROOT.join(SPECS.fetch(provider)).to_s

    # @param values [Array<Float>]
    # @return [Float]
    def median(values)
      return 0.0 if values.empty?

      sorted = values.sort
      middle = sorted.size / 2
      sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end
  end

  # Печать итога таблицами markdown: замер должен попадать в отчёт как есть.
  class Report
    # @param suite [Suite] отработавший прогон
    def initialize(suite)
      @suite = suite
      @measurements = suite.measurements
      @kinds = @measurements.map(&:kind).uniq
    end

    # @return [String]
    def to_s
      [accuracy, speed, spending, mistakes].compact.join("\n")
    end

    # @return [Hash] то же самое машиночитаемо
    def to_h
      { measurements: @measurements.map(&:to_h),
        pipeline_without_classification: @suite.pipeline_without_classification,
        meters: @suite.meters.transform_values { |meter| meter_of(meter) } }
    end

    private

    # @return [Array<String>] описания, на которых мерили
    def providers = @measurements.map(&:provider).uniq

    # @return [String] сколько ролей размечено верно
    def accuracy
      rows = @kinds.map do |kind|
        cells = providers.map { |provider| "#{correct(kind, provider)}/4" }
        "| #{kind} | #{cells.join(" | ")} | #{correct(kind)}/#{providers.size * 4} |"
      end
      table("Точность", ["способ", *providers, "всего"], rows)
    end

    # @return [String] сколько занимает сама разметка
    def speed
      rows = @kinds.map do |kind|
        seconds = @measurements.select { |item| item.kind == kind }.map(&:seconds)
        "| #{kind} | #{seconds.size} | #{ms(@suite.median_of(kind))} | " \
          "#{ms(seconds.min)} | #{ms(seconds.max)} |"
      end
      table("Скорость разметки одного описания", %w[способ прогонов медиана мин макс], rows) +
        "\nОстальной конвейер, без разметки: #{ms(@suite.pipeline_without_classification)}\n"
    end

    # @return [String, nil] во что обошлись походы наружу
    def spending
      return nil if @suite.meters.empty?

      rows = @suite.meters.map do |kind, meter|
        spent = meter_of(meter)
        "| #{kind} | #{spent.fetch(:calls)} | #{spent.fetch(:input)} | " \
          "#{spent.fetch(:output)} | $#{format("%.4f", spent.fetch(:cost))} |"
      end
      table("Расход", ["способ", "запросов", "токенов на вход", "на выход", "цена"], rows)
    end

    # @return [String, nil] что именно размечено неверно
    def mistakes
      wrong = @measurements.reject { |item| item.mistakes.empty? }
                           .group_by { |item| [item.kind, item.provider] }
      return nil if wrong.empty?

      lines = wrong.map do |(kind, provider), items|
        "- #{kind}, #{provider}: #{items.first.mistakes.join("; ")}"
      end
      "\n### Ошибки\n\n#{lines.uniq.join("\n")}\n"
    end

    # @param meter [Meter, Counter]
    # @return [Hash] запросы, токены и цена
    def meter_of(meter)
      return counted(meter) if meter.is_a?(Counter)

      model = ENV.fetch("RSOCKET_LLM_MODEL", Adapter::Classification::Llm::DEFAULT_MODEL)
      spent = { input: meter.input, output: meter.output, cached: meter.cached }
      { calls: meter.calls, **spent, cost: price_of(spent, PRICES.fetch(model)) }
    end

    # @param spent [Hash{Symbol => Integer}] токены по видам
    # @param price [Hash{Symbol => Float}] цена за миллион токенов каждого вида
    # @return [Float] доллары
    def price_of(spent, price)
      spent.sum { |kind, tokens| tokens * price.fetch(kind) } / 1e6
    end

    # @param meter [Counter]
    # @return [Hash]
    def counted(meter)
      price = PRICES.fetch(ENV.fetch("VOYAGE_MODEL", Adapter::Embedding::Voyage::DEFAULT_MODEL))
      { calls: meter.calls, input: meter.tokens, output: 0, cached: 0,
        cost: meter.tokens * price.fetch(:input) / 1e6 }
    end

    # @param kind [String]
    # @param provider [String, nil] nil — по всем описаниям
    # @return [Integer] верных ролей в одном прогоне
    def correct(kind, provider = nil)
      chosen = @measurements.select do |item|
        item.kind == kind && (provider.nil? || item.provider == provider)
      end
      chosen.group_by(&:provider).sum { |_, items| items.first.correct }
    end

    # @return [String]
    def table(title, header, rows)
      divider = header.map { "---" }
      "\n### #{title}\n\n| #{header.join(" | ")} |\n" \
        "| #{divider.join(" | ")} |\n#{rows.join("\n")}\n"
    end

    # @param seconds [Float]
    # @return [String]
    def ms(seconds)
      return "#{(seconds * 1e6).round} мкс" if seconds < 0.001
      return "#{(seconds * 1000).round(1)} мс" if seconds < 1

      "#{seconds.round(2)} с"
    end
  end
end

kinds = ARGV.empty? ? Bench::RUNS.keys : ARGV
providers = ENV["BENCH_PROVIDERS"]&.split(",") || Bench::TRUTH.keys
runs = Bench::RUNS.merge(ENV["BENCH_RUNS"] ? kinds.to_h { |k| [k, ENV["BENCH_RUNS"].to_i] } : {})
pauses = ENV["BENCH_PAUSE"] ? kinds.to_h { |k| [k, ENV["BENCH_PAUSE"].to_f] } : Bench::PAUSES
suite = Bench::Suite.new(kinds: kinds, providers: providers, runs: runs, pauses: pauses)
suite.call
report = Bench::Report.new(suite)
puts report
File.write(ENV["BENCH_JSON"], JSON.pretty_generate(report.to_h)) if ENV["BENCH_JSON"]
