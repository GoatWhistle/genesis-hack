# frozen_string_literal: true

# Классификатор — сменная часть сценария: правила, эмбеддинги и запрос в модель
# подставляются одинаково. Проверяется именно подстановка, а не сами способы —
# у каждого из них свои проверки.
RSpec.describe Rsocket do
  describe ".classifier" do
    it "по имени отдаёт классификатор на правилах" do
      expect(described_class.classifier("rules", rules))
        .to be_a(Service::AdapterBuilder::Classification::Classifier)
    end

    it "по имени отдаёт классификатор на эмбеддингах" do
      expect(described_class.classifier("embeddings", rules))
        .to be_a(Adapter::Classification::Embeddings)
    end

    it "по имени отдаёт классификатор на модели" do
      expect(described_class.classifier("llm", rules)).to be_a(Adapter::Classification::Llm)
    end

    it "пропускает готовый объект как есть: клиент переживает несколько сборок" do
      ready = Adapter::Classification::Embeddings.new(rules, embedder: StubEmbedder.new([]))
      expect(described_class.classifier(ready, rules)).to be(ready)
    end

    it "говорит, что известно, когда имени не знает" do
      expect { described_class.classifier("вектора", rules) }
        .to raise_error(ArgumentError, /Известны: rules, embeddings, llm/)
    end
  end

  describe Service::AdapterBuilder::Builder do
    it "без указаний раздаёт роли правилами" do
      expect(build_service("novapay").report.dig("roles", "create_request", "why"))
        .to include("счёт 15 при пороге 10")
    end

    it "собирает тем классификатором, который ему дали" do
      result = Rsocket.builder(rules: rules, classifier: llm)
                      .call(reference: example_spec("novapay"), provider: "novapay")
      expect(result.report.dig("roles", "create_request", "why")).to include("узнала сама")
    end

    it "не принимает объект, который раздавать роли не умеет" do
      expect { Rsocket.builder(rules: rules, classifier: "самотёком") }
        .to raise_error(ArgumentError, /неизвестный классификатор/)
    end
  end

  # Модель, «узнавшая» две обязательные роли: без них сборка не идёт, а
  # необязательные здесь ни при чём.
  def llm
    Adapter::Classification::Llm.new(
      rules,
      client: StubClaude.assigning(
        { role: "create_request", operation: 1, confidence: 0.9, reason: "узнала сама" },
        { role: "fetch_status", operation: 2, confidence: 0.9, reason: "узнала сама" }
      )
    )
  end
end
