# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::Scoring do
  subject(:scoring) { described_class.new(weights) }

  let(:weights) do
    { "thresholds" => {
      "confident" => 5.0, "needs_confirmation" => 2.0, "min_signals_for_confident" => 2
    } }
  end

  def evidence(signal, weight)
    Rsocket::Classify::Evidence.new(signal: signal, detail: "признак", weight: weight)
  end

  it "складывает веса признаков" do
    expect(scoring.score([evidence(:lexicon, 1.5), evidence(:signature, 2.0)])).to eq(3.5)
  end

  it "не угадывает ниже нижнего порога" do
    expect(scoring.verdict([evidence(:lexicon, 1.9)])).to eq(:unknown)
  end

  it "просит подтверждения между порогами" do
    expect(scoring.verdict([evidence(:lexicon, 3.0)])).to eq(:needs_confirmation)
  end

  it "уверен, когда роль подтверждают разные признаки" do
    found = [evidence(:lexicon, 3.0), evidence(:signature, 2.5)]

    expect(scoring.verdict(found)).to eq(:confident)
  end

  # Совпадение слов без подтверждения формой запроса — это совпадение слов.
  it "не выдаёт уверенный вердикт по одному сигналу, каким бы сильным он ни был" do
    expect(scoring.verdict([evidence(:lexicon, 6.0), evidence(:lexicon, 4.0)]))
      .to eq(:needs_confirmation)
  end

  it "берёт пороги из словаря, а не из кода" do
    strict = described_class.new(
      "thresholds" => { "confident" => 99.0, "needs_confirmation" => 50.0 }
    )

    expect(strict.verdict([evidence(:lexicon, 10.0)])).to eq(:unknown)
  end
end
