# frozen_string_literal: true

# Половина примеров нарочно портит сервис: проверка обязана это поймать.
# Сеть настоящая, но своя — подставной провайдер на локальном порту.
RSpec.describe "проверка собранного класса на фикстурах" do
  subject(:report) { check(result.source) }

  let(:result) { build_service("novapay") }
  let(:tester) { Service::AdapterBuilder::Testing::Tester.new(rules) }

  # @param source [String] исходник, который проверяем
  # @return [Service::AdapterBuilder::Testing::Report]
  def check(source) = tester.call(source: source, blueprint: result.blueprint)

  # @param from [String] что испортить в собранном сервисе
  # @param to [String] чем заменить
  # @return [Array<String>] названия проверок, которые на этом не сошлись
  def failures(from, to)
    check(result.source.sub(from, to)).failed.map(&:title)
  end

  describe "на неиспорченном сервисе" do
    it "расхождений не находит" do
      expect(report).to be_ok
    end

    it "дёргает каждую роль: и те, что ходят к провайдеру, и приём уведомления" do
      expect(report.checks.map(&:role).uniq)
        .to include(:create_request, :fetch_status, :cancel_request, :process_callback)
    end

    it "проверяет и успешный ответ, и каждый описанный отказ" do
      expect(report.checks.map(&:title)).to include(a_string_including("успешный ответ"),
                                                    a_string_including("ответ 429"))
    end

    it "рассказывает о себе одной строкой" do
      expect(report.summary).to match(/проверок: \d+, прошло: \d+, не прошло: 0/)
    end
  end

  describe "когда собранный сервис испорчен" do
    it "видит запрос, ушедший не по тому адресу" do
      expect(failures('request(:post, "/payouts"', 'request(:post, "/wrong"'))
        .to include("запрос уходит на POST /payouts")
    end

    it "видит запрос, ушедший без ключа авторизации" do
      expect(failures('message["X-API-Key"] = credential(:api_key)', "nil"))
        .to include("запрос подписан: ApiKeyAuth")
    end

    it "видит потерянное поле тела запроса" do
      expect(failures("external_id: operation.id,", ""))
        .to include(a_string_including("в теле запроса поля провайдера"))
    end

    it "видит идентификатор операции, прочитанный не оттуда" do
      expect(failures('dig_body(response.body, "id")', 'dig_body(response.body, "currency")'))
        .to include("идентификатор операции прочитан из ответа")
    end

    it "видит неверный перевод состояния провайдера" do
      expect(failures('"pending" => "in_progress"', '"pending" => "rejected"'))
        .to include(a_string_including("состояние из ответа переведено в статус контракта"))
    end

    it "видит отказ провайдера, разобранный не тем кодом" do
      expect(failures("429 => %i[rate_limit too_many_requests]", "429 => %i[not_found not_found]"))
        .to include("ответ 429 разобран как отказ rate_limit")
    end

    it "видит уведомление, обёрнутое не тем статусом контракта" do
      expect(failures('"payout.completed" => "approved"', '"payout.completed" => "in_progress"'))
        .to include("уведомление payout.completed переводится в approved")
    end

    # Сборку это не роняет: файлы уже напечатаны.
    it "не роняет сборку на исходнике, который не загружается" do
      broken = check("class Broken")
      expect(broken.failed.map(&:title)).to eq(["собранный класс загружается и создаётся"])
    end
  end

  describe "на другом контракте" do
    let(:result) { build_service("novapay", contract: "plain_client") }
    let(:tester) do
      Service::AdapterBuilder::Testing::Tester.new(rules("plain_client"))
    end

    it "дёргает клиент его же способом: платёж хешем, отказ исключением" do
      expect(report).to be_ok
    end
  end

  describe "когда профиль контракта не приносит пробы" do
    let(:tester) do
      settings = Config::Importer.call(DEFAULT_CONTRACT)
      settings.contract.probe = nil
      Service::AdapterBuilder::Testing::Tester.new(settings)
    end

    it "не проверяет ничего и честно говорит почему" do
      expect(report).to have_attributes(checks: [], notes: [a_string_including("probe.rb")])
    end
  end
end
