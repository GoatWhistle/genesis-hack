# frozen_string_literal: true

# Классификатор — сменная часть; проверяется подстановка, а не сами способы.
RSpec.describe Rsocket do
  describe ".classifier" do
    it "по имени отдаёт классификатор на правилах" do
      expect(described_class.classifier("rules", rules))
        .to be_a(Service::AdapterBuilder::Classification::Classifier)
    end

    it "пропускает готовый объект как есть: клиент переживает несколько сборок" do
      ready = Service::AdapterBuilder::Classification::Classifier.new(rules)
      expect(described_class.classifier(ready, rules)).to be(ready)
    end

    it "перечисляет то, что умеет, когда имени не знает" do
      expect { described_class.classifier("вектора", rules) }
        .to raise_error(ArgumentError, /Известны: #{Rsocket::CLASSIFIERS.keys.join(", ")}/)
    end
  end

  # Проверка — тоже сменная часть, и просят её явно.
  describe ".tester" do
    it "по просьбе отдаёт проверку на подставном провайдере" do
      expect(described_class.tester(true, rules))
        .to be_a(Service::AdapterBuilder::Testing::Tester)
    end

    it "без просьбы не проверяет ничего" do
      expect(described_class.tester(nil, rules)).to be_nil
    end

    it "пропускает готовый объект как есть" do
      ready = Service::AdapterBuilder::Testing::Tester.new(rules)
      expect(described_class.tester(ready, rules)).to be(ready)
    end
  end

  describe Service::AdapterBuilder::Builder do
    it "без указаний раздаёт роли правилами" do
      expect(build_service("novapay").report.dig("roles", "create_request", "why"))
        .to include("счёт 22 при пороге 13")
    end

    it "собирает тем классификатором, который ему дали" do
      ready = Service::AdapterBuilder::Classification::Classifier.new(rules)
      result = Rsocket.builder(rules: rules, classifier: ready)
                      .call(reference: example_spec("novapay"), provider: "novapay")
      expect(result.report.dig("roles", "create_request", "why")).to include("счёт 22")
    end

    it "не принимает объект, который раздавать роли не умеет" do
      expect { Rsocket.builder(rules: rules, classifier: "самотёком") }
        .to raise_error(ArgumentError, /неизвестный классификатор/)
    end

    it "без проверки сборка идёт как раньше и ничего не исполняет" do
      expect(build_service("novapay").checks).to be_nil
    end

    it "с проверкой кладёт её итог рядом с разбором" do
      result = Rsocket.builder(rules: rules, tester: true)
                      .call(reference: example_spec("novapay"), provider: "novapay")
      expect(result.checks).to be_ok
    end

    it "не принимает объект, который проверять не умеет" do
      expect { Rsocket.builder(rules: rules, tester: "на глаз") }
        .to raise_error(ArgumentError, /проверяльщик не отвечает/)
    end
  end
end
