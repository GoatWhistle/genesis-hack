# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Adapter::Embedding::Voyage do
  subject(:client) { described_class.new(api_key: "ключ") }

  let(:endpoint) { described_class::ENDPOINT }

  # Voyage нумерует записи ответа сам; порядок в списке он не обещает, поэтому
  # ответ намеренно перемешан.
  def answer(*vectors)
    data = vectors.each_with_index.map { |vector, index| { index: index, embedding: vector } }
    { status: 200, body: JSON.generate(data: data.reverse) }
  end

  it "отдаёт векторы в порядке текстов, а не ответа" do
    stub_request(:post, endpoint).to_return(answer([1.0, 0.0], [0.0, 1.0]))
    expect(client.embed(%w[первый второй])).to eq([[1.0, 0.0], [0.0, 1.0]])
  end

  it "просит ту модель, которую ей назвали" do
    stub_request(:post, endpoint).to_return(answer([1.0]))
    client.embed(%w[текст])
    expect(a_request(:post, endpoint)
      .with(body: hash_including("model" => described_class::DEFAULT_MODEL))).to have_been_made
  end

  it "подписывается ключом" do
    stub_request(:post, endpoint).to_return(answer([1.0]))
    client.embed(%w[текст])
    expect(a_request(:post, endpoint)
      .with(headers: { "Authorization" => "Bearer ключ" })).to have_been_made
  end

  it "разбивает длинный список на пачки" do
    stub_const("#{described_class}::BATCH", 2)
    stub_request(:post, endpoint).to_return(answer([1.0], [2.0]), answer([3.0]))
    expect(client.embed(%w[раз два три])).to eq([[1.0], [2.0], [3.0]])
  end

  it "не ходит в сеть за пустым списком" do
    expect(client.embed([])).to eq([])
  end

  describe "когда сервис отказал временно" do
    before { stub_const("#{described_class}::BACKOFF", 0) }

    it "повторяет запрос" do
      stub_request(:post, endpoint)
        .to_return({ status: 429, body: "перебор" }, answer([1.0]))
      expect(client.embed(%w[текст])).to eq([[1.0]])
    end

    # Пауза по умолчанию здесь обнулена, поэтому задержку создаёт только то,
    # о чём попросил сам сервис.
    it "ждёт столько, сколько попросил сервис" do
      stub_request(:post, endpoint)
        .to_return({ status: 429, headers: { "retry-after" => "0.2" } }, answer([1.0]))
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.embed(%w[текст])
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 0.2
    end

    it "сдаётся, когда попытки кончились" do
      stub_request(:post, endpoint).to_return(status: 503, body: "лёг")
      expect { client.embed(%w[текст]) }
        .to raise_error(described_class::Error, /ответил 503/)
    end
  end

  describe "когда отказ повтором не лечится" do
    before { stub_request(:post, endpoint).to_return(status: 400, body: "не та модель") }

    it "передаёт отказ наверх" do
      expect { client.embed(%w[текст]) }.to raise_error(described_class::Error, /ответил 400/)
    end

    it "не тратит попытки впустую" do
      attempt
      expect(a_request(:post, endpoint)).to have_been_made.once
    end

    # Сам отказ проверяется примером выше, здесь важно только число запросов.
    def attempt
      client.embed(%w[текст])
    rescue described_class::Error
      nil
    end
  end

  it "говорит прямо, что ключа нет" do
    expect { described_class.new(api_key: nil).embed(%w[текст]) }
      .to raise_error(described_class::Error, /VOYAGE_API_KEY/)
  end
end
