# frozen_string_literal: true

RSpec.describe Adapter::Classification::Embeddings do
  subject(:bindings) { classifier.call(operations) }

  # Углы вместо координат: близость двух текстов — это угол между ними, и так
  # видно, что именно проверяется. Роли идут в порядке конфига: создание,
  # статус-запрос, webhook, отмена.
  #
  # Пара «отмена × первая операция» — самая близкая во всём наборе (2°), но
  # первой роль разбирается создание, и его ближайшая операция — та же первая
  # (18°). Правило с очками отдало бы её создающей роли просто потому, что та
  # объявлена раньше.
  let(:roles) { [0, 90, 95, 20].map { |angle| StubEmbedder.at(angle) } }
  let(:candidates) { [18, 40].map { |angle| StubEmbedder.at(angle) } }
  let(:embedder) { StubEmbedder.new(roles + candidates) }
  let(:operations) { operations_for("swiftpay").first(2) }
  let(:classifier) { described_class.new(rules, embedder: embedder, threshold: 0.7) }

  it "отдаёт роли операцию, к эталону которой она ближе всех" do
    expect(bindings.fetch(:cancel_request).operation.method_name).to eq("submit_transfer")
  end

  it "разбирает пары по близости, а не по порядку ролей" do
    expect(bindings.fetch(:create_request).operation.method_name).to eq("fetch_transfer")
  end

  it "не отдаёт одну операцию двум ролям" do
    claimed = bindings.values.select(&:bound?).map(&:operation)
    expect(claimed.uniq.size).to eq(claimed.size)
  end

  it "оставляет роль без операции, когда ближе порога никого нет" do
    expect(bindings.fetch(:fetch_status)).not_to be_bound
  end

  it "называет в заглушке ближайшего кандидата и порог" do
    expect(bindings.fetch(:fetch_status).explanation)
      .to include("fetch_transfer", "0.643", "0.7")
  end

  it "объясняет назначение близостью" do
    expect(bindings.fetch(:cancel_request).explanation).to include("близость", "при пороге")
  end

  it "меряет решение своей шкалой, а не порогом правил" do
    expect(bindings.fetch(:cancel_request).threshold).to eq(0.7)
  end

  describe "когда в описании нет операций" do
    let(:operations) { [] }

    it "отдаёт одни заглушки" do
      expect(bindings.values).to all(satisfy { |binding| !binding.bound? })
    end
  end

  describe "когда сервис вернул не столько векторов, сколько текстов" do
    let(:embedder) { StubEmbedder.new(roles) }

    it "останавливает разбор, а не считает по остаткам" do
      expect { bindings }.to raise_error(/вернул 4 векторов вместо 6/)
    end
  end
end
