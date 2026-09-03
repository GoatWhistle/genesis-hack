# frozen_string_literal: true

require "spec_helper"

# Словари — данные, от которых зависит весь разбор смысла. Проверяем не
# «файл существует», а что в нём лежит то, на что рассчитывает код: иначе
# опечатка в YAML превращается в тихо неверный вердикт.
RSpec.describe Rsocket::Dictionaries do
  subject(:dictionaries) { described_class.new }

  it "читает все объявленные словари" do
    described_class::FILES.each do |name|
      expect(dictionaries.public_send(name)).not_to be_empty, "пустой словарь #{name}.yml"
    end
  end

  it "даёт каждой роли название человеческими словами" do
    titles = dictionaries.operations.values.map { |role| role["title"] }

    expect(titles).to all(be_a(String))
  end

  it "описывает каждую роль хотя бы одним сильным словом" do
    weak_roles = dictionaries.operations.reject { |_id, role| role["strong"]&.any? }

    expect(weak_roles.keys).to be_empty
  end

  it "переводит статусы только в наш канонический набор" do
    canonical = %w[created processing succeeded rejected cancelled refunded needs_review]

    expect(dictionaries.statuses.keys).to match_array(canonical)
  end

  it "не повторяет одно значение статуса в двух канонических" do
    values = dictionaries.statuses.values.flatten

    expect(values).to eq(values.uniq)
  end

  it "относит коды ответов к известным классам ошибок" do
    known = dictionaries.errors["by_words"].keys

    expect(dictionaries.errors["by_code"].values.uniq - known).to be_empty
  end

  it "задаёт оба порога и требование к числу признаков" do
    expect(dictionaries.weights["thresholds"]).to include(
      "confident", "needs_confirmation", "min_signals_for_confident"
    )
  end

  it "объясняет, что искать, а не падает, когда словаря нет" do
    expect { described_class.new("/nowhere").operations }
      .to raise_error(Rsocket::Error, /нет словаря operations\.yml/)
  end
end
