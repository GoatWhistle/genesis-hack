# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Builder do
  subject(:result) { build_service("novapay") }

  it "печатает запрос к эндпоинту создания выплаты" do
    expect(result.source).to include('request(:post, "/payouts"')
  end

  it "подставляет параметр пути в адрес статус-запроса" do
    expect(result.source)
      .to include("request(:get, \"/payouts/\#{operation.provider_operation_id}\")")
  end

  it "передаёт ключ идемпотентности заголовком, как его назвал провайдер" do
    expect(result.source).to include('headers: { "Idempotency-Key" => operation.id }')
  end

  it "кладёт в отчёт эндпоинт каждой роли" do
    expect(result.report.dig("roles", "create_request")).to include("endpoint" => "POST /payouts")
  end

  # Точное число не закрепляем: веса правил меняются, а требование — чтобы счёт
  # был записан и покрывал порог, по которому роль и назначена.
  it "кладёт в отчёт счёт, покрывающий порог роли" do
    role = result.report.dig("roles", "create_request")
    expect(role["score"]).to be >= role["threshold"]
  end

  it "отмечает в отчёте роль, оставшуюся заглушкой" do
    report = build_service("plainpay").report
    expect(report.dig("roles", "process_callback", "status")).to eq("заглушка")
  end

  it "называет в отчёте выбранную схему авторизации" do
    expect(result.report.dig("auth", "primary")).to eq("ApiKeyAuth (api_key)")
  end

  describe "когда провайдер предлагает несколько схем авторизации" do
    it "выбирает одну и перечисляет остальные" do
      report = build_service("kassabox").report
      expect(report.dig("auth", "alternatives")).not_to be_empty
    end
  end

  describe "когда авторизация в описании не указана" do
    it "честно пишет об этом в предупреждениях" do
      report = build_service("nordbank").report
      expect(report.fetch("warnings").join(" ")).to include("securitySchemes")
    end
  end

  describe "когда обязательная роль не распозналась" do
    subject(:build) do
      described_class.new(spec_source: empty_source, renderer: described_class, rules: rules)
                     .call(reference: example_spec("novapay"), provider: "novapay")
    end

    # Описание без единого пути: ролям не из чего выбирать.
    let(:empty_source) do
      Class.new do
        include Service::AdapterBuilder::Ports::SpecSource

        def read(_reference) = { info: { title: "пусто" }, paths: {} }
      end.new
    end

    it "останавливает сборку и называет роли" do
      expect { build }.to raise_error(/не распознаны обязательные роли/)
    end
  end

  describe "когда правила подсунуты неполные" do
    it "порт проверяет их на входе" do
      expect { described_class.new(spec_source: nil, renderer: nil, rules: Object.new) }
        .to raise_error(ArgumentError, /не отвечает на/)
    end
  end
end
