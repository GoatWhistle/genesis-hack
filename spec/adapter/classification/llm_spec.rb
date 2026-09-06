# frozen_string_literal: true

RSpec.describe Adapter::Classification::Llm do
  subject(:bindings) { classifier.call(operations) }

  let(:operations) { operations_for("novapay") }
  let(:classifier) { described_class.new(rules, client: client, threshold: 0.6) }

  # Номера операций — те же, что уходят модели: novapay объявляет создание,
  # статус-запрос, отмену, webhook и баланс именно в этом порядке.
  def verdict(role, operation, confidence: 0.95, reason: "похоже")
    { role: role, operation: operation, confidence: confidence, reason: reason }
  end

  describe "когда модель разметила всё" do
    let(:client) do
      StubClaude.assigning(verdict("create_request", 1), verdict("fetch_status", 2),
                           verdict("cancel_request", 3), verdict("process_callback", 4))
    end

    it "раздаёт роли так, как сказала модель" do
      expect(bindings.transform_values { |item| item.operation&.method_name })
        .to eq(create_request: "create_payout", fetch_status: "get_payout_status",
               process_callback: "payout_webhook", cancel_request: "cancel_payout")
    end

    it "объясняет решение словами модели" do
      expect(bindings.fetch(:create_request).explanation)
        .to include("уверенность 0.95", "при пороге 0.6", "похоже")
    end

    it "меряет решение уверенностью, а не очками правил" do
      expect(bindings.fetch(:create_request).score).to eq(0.95)
    end

    it "не пересказывает модели правила распознавания" do
      classifier.call(operations)
      expect(client.asked.fetch(:messages).first.fetch(:content)).not_to include("submit")
    end
  end

  describe "когда модель написала про роль несколько строк" do
    let(:client) do
      StubClaude.assigning(verdict("create_request", 5, confidence: 0.2, reason: "нет"),
                           verdict("create_request", 1, confidence: 0.9, reason: "да"))
    end

    it "оставляет ту, в которой она уверена больше" do
      expect(bindings.fetch(:create_request).operation.method_name).to eq("create_payout")
    end
  end

  describe "когда подходящей операции модель не нашла" do
    let(:client) { StubClaude.assigning(verdict("process_callback", 0, reason: "webhook нет")) }

    it "оставляет роль заглушкой" do
      expect(bindings.fetch(:process_callback)).not_to be_bound
    end

    it "передаёт в отчёт объяснение модели" do
      expect(bindings.fetch(:process_callback).explanation).to include("webhook нет")
    end
  end

  describe "когда модель не уверена" do
    let(:client) { StubClaude.assigning(verdict("create_request", 1, confidence: 0.3)) }

    it "не назначает роль: пустая честнее неверной" do
      expect(bindings.fetch(:create_request)).not_to be_bound
    end

    it "говорит в отчёте, что уверенности не хватило" do
      expect(bindings.fetch(:create_request).explanation).to include("ниже порога")
    end
  end

  describe "когда модель отдала одну операцию двум ролям" do
    let(:client) do
      StubClaude.assigning(verdict("create_request", 1), verdict("cancel_request", 1))
    end

    it "оставляет её роли, объявленной раньше" do
      expect(bindings.fetch(:create_request).operation.method_name).to eq("create_payout")
    end

    it "второй роли не достаётся ничего" do
      expect(bindings.fetch(:cancel_request)).not_to be_bound
    end
  end

  describe "когда модель ответила прозой вместо разметки" do
    let(:client) { StubClaude.talking }

    it "останавливает сборку, а не собирает по пустой разметке" do
      expect { bindings }.to raise_error(described_class::Error, /не вызвал инструмент/)
    end
  end

  describe "когда в описании нет операций" do
    let(:operations) { [] }
    let(:client) { StubClaude.talking }

    it "не тратит запрос впустую" do
      expect(bindings.values).to all(satisfy { |binding| !binding.bound? })
    end
  end
end
