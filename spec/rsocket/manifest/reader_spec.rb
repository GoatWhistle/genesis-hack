# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Rsocket::Manifest::Reader do
  let(:spec) { ir("novapay") }
  let(:computed) { Rsocket::Classify::Classifier.call(spec) }

  def apply(document)
    described_class.new(document).apply(computed, spec)
  end

  # Ради этого файл и существует: инженер поправил роль — следующий прогон
  # обязан её уважать, а не переубеждать человека своей оценкой.
  it "ставит роль на операцию, выбранную человеком" do
    result = apply("roles" => { "balance" => { "operation" => "GET /payouts/{payout_id}" } })

    expect(result.roles[:balance].operation.path).to eq("/payouts/{payout_id}")
  end

  it "объясняет в отчёте, что роль выбрана человеком" do
    result = apply("roles" => { "balance" => { "operation" => "GET /payouts/{payout_id}" } })

    expect(result.roles[:balance].evidence.map(&:detail))
      .to include(a_string_matching(/задана человеком/))
  end

  it "снимает роль, если человек стёр операцию" do
    result = apply("roles" => { "balance" => { "operation" => nil } })

    expect(result.roles).not_to have_key(:balance)
  end

  # Файл, записанный прошлым прогоном, — это не правка человека. Приняв его за
  # правку, инструмент терял бы обоснования на втором же запуске.
  it "сохраняет обоснование, когда файл повторяет наш собственный вывод" do
    result = apply("roles" => { "balance" => { "operation" => "GET /balance" } })

    expect(result.roles[:balance].evidence.size).to eq(computed.roles[:balance].evidence.size)
  end

  it "принимает перевод статуса, заданный руками" do
    result = apply("statuses" => { "pending" => "needs_review" })
    found = result.statuses.find { |status| status.provider_value == "pending" }

    expect(found.canonical).to eq(:needs_review)
  end

  it "принимает единицы суммы, заданные руками" do
    expect(apply("money" => { "unit" => "decimal" }).money.unit).to eq(:decimal)
  end

  it "принимает класс ошибки, заданный руками" do
    result = apply("errors" => { "by_http_code" => { "429" => "final" } })
    found = result.errors.find { |error| error.http_code == 429 }

    expect(found.klass).to eq(:final)
  end

  it "принимает алгоритм подписи, заданный руками" do
    result = apply("webhook" => { "algorithm" => "hmac_sha512" })

    expect(result.webhook.algorithm).to eq(:hmac_sha512)
  end

  it "не молчит про операцию из файла, которой нет в описании" do
    result = apply("roles" => { "balance" => { "operation" => "GET /nowhere" } })

    expect(result.notes.map(&:message)).to include(a_string_matching(/которой нет в описании/))
  end

  it "оставляет автоматический вывод, когда правка указывает в никуда" do
    result = apply("roles" => { "balance" => { "operation" => "GET /nowhere" } })

    expect(result.roles[:balance].operation.path).to eq("/balance")
  end

  it "ничего не меняет, когда файла нет" do
    expect(described_class.load("/nowhere/mapping.yml")).to be_nil
  end

  it "объясняет, а не падает, если файл догадок сломан" do
    broken = Tempfile.new(["mapping", ".yml"])
    broken.write("roles: [не закрытая скобка\n")
    broken.close

    expect { described_class.load(broken.path) }
      .to raise_error(Rsocket::Error, /файл догадок не читается/)
  end
end
