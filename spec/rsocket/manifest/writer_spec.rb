# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Rsocket::Manifest::Writer do
  subject(:document) { YAML.safe_load(yaml) }

  let(:spec) { ir("novapay") }
  let(:result) { Rsocket::Classify::Classifier.call(spec) }
  let(:yaml) { described_class.new(result, spec).to_yaml }

  it "начинается с объяснения, что это за файл" do
    expect(yaml).to start_with("# Что RSOCKET понял из описания API этого провайдера.")
  end

  it "называет провайдера словами из описания" do
    expect(document["provider"]).to eq("NovaPay Payout API")
  end

  it "показывает операцию каждой роли" do
    expect(document.dig("roles", "create_payout", "operation")).to eq("POST /payouts")
  end

  # Файл читает человек, который наш код не видел: без объяснения он не сможет
  # ни согласиться с догадкой, ни поправить её осмысленно.
  it "объясняет каждую роль словами" do
    expect(document.dig("roles", "create_payout", "why"))
      .to include(a_string_matching(/содержит «create»/))
  end

  it "кладёт перевод статусов плоскими парами, которые удобно править" do
    expect(document["statuses"]).to include("completed" => "succeeded")
  end

  it "записывает единицы суммы и поле, к которому они относятся" do
    expect(document["money"]).to include("unit" => "minor", "field" => "amount")
  end

  it "записывает разбор уведомлений" do
    expect(document["webhook"])
      .to include("signature_header" => "X-NovaPay-Signature", "algorithm" => "hmac_sha256")
  end

  it "переносит в файл всё, что требует внимания" do
    expect(document["notes"]).to include(a_hash_including("level" => "needs_confirmation"))
  end

  it "не пишет в файл символов Ruby" do
    expect(yaml).not_to match(/: :[a-z]/)
  end

  # В файле нет ни времени создания, ни версии инструмента: одинаковый вход
  # обязан давать одинаковый файл, иначе его нельзя держать в системе контроля
  # версий и нельзя сравнивать прогоны.
  it "даёт побайтово одинаковый файл на одном и том же описании" do
    expect(described_class.new(result, spec).to_yaml).to eq(yaml)
  end

  it "пишет файл на диск" do
    Tempfile.create(["mapping", ".yml"]) do |file|
      described_class.new(result, spec).write(file.path)

      expect(File.read(file.path)).to eq(yaml)
    end
  end
end
