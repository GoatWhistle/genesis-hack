# frozen_string_literal: true

require "json"

# Одна сборка отдаёт три файла; проверяем состав, а не текст целиком.
RSpec.describe "выходные файлы сборки" do
  subject(:result) { build_service("novapay") }

  let(:fixtures) { JSON.parse(result.files.fetch("fixtures.json")) }
  let(:guide) { result.files.fetch("INTEGRATION.md") }

  # Отчёт уходит тем же путём, что и остальные файлы.
  it "печатает набор файлов профиля и кладёт рядом отчёт" do
    expect(result.files.keys)
      .to eq(%w[novapay_service.rb INTEGRATION.md fixtures.json mapping.yml])
  end

  describe "фикстуры" do
    it "разбирается как JSON" do
      expect { JSON.parse(result.files.fetch("fixtures.json")) }.not_to raise_error
    end

    it "называет разделы именами ролей контракта" do
      expect(fixtures.keys).to include("create_request", "fetch_status", "callbacks")
    end

    # Пример, написанный провайдером, точнее синтезированного по схеме.
    it "берёт пример запроса из описания" do
      expect(fixtures.dig("create_request", "request"))
        .to include("amount" => 1_500_000, "currency" => "RUB", "external_id" => "op_abc123")
    end

    it "приводит примеры всех описанных ответов, а не только успешного" do
      expect(fixtures.dig("create_request", "responses").keys)
        .to include("201", "402", "422", "429")
    end

    it "подставляет в ответ те значения, которые назвал провайдер" do
      expect(fixtures.dig("create_request", "responses", "201"))
        .to include("id" => "np_7f3a9b2c", "status" => "pending")
    end

    it "даёт по уведомлению на каждое событие" do
      expect(fixtures.fetch("callbacks").keys)
        .to contain_exactly("payout.completed", "payout.failed", "payout.processing",
                            "payout.cancelled")
    end

    it "держит событие и состояние в теле согласованными" do
      expect(fixtures.dig("callbacks", "payout.failed", "payload"))
        .to include("event" => "payout.failed", "status" => "failed")
    end

    it "называет статус, которым обёртка ответит на уведомление" do
      expect(fixtures.dig("callbacks", "payout.completed", "expected_operation_status"))
        .to eq("approved")
    end

    describe "когда провайдер не описывает уведомления" do
      subject(:result) { build_service("swiftpay") }

      it "оставляет раздел пустым, а не выдумывает примеры" do
        expect(fixtures.fetch("callbacks")).to be_empty
      end
    end
  end

  describe "инструкция" do
    it "называет переменные окружения для адреса и ключа" do
      expect(guide).to include("`NOVAPAY_BASE_URL`", "`NOVAPAY_API_KEY`")
    end

    it "описывает выбранную схему авторизации" do
      expect(guide).to include("ApiKeyAuth", "X-API-Key")
    end

    it "перечисляет методы контракта с эндпоинтами провайдера" do
      expect(guide).to include("`create_request` | POST /payouts",
                               "`fetch_status` | GET /payouts/{payout_id}")
    end

    it "называет заголовок идемпотентности рядом с методом" do
      expect(guide).to include("создание выплаты | Idempotency-Key")
    end

    it "печатает таблицу статусов" do
      expect(guide).to include("| `completed` | `approved` |", "| `failed` | `rejected` |")
    end

    it "печатает таблицу ошибок с действиями" do
      expect(guide).to include("| 429 | `rate_limit` | retry_backoff |")
    end

    it "объясняет подпись уведомления" do
      expect(guide).to include("SHA256", "X-NovaPay-Signature")
    end

    it "переносит в инструкцию то, что просит проверить руками" do
      expect(guide).to include(*result.blueprint.warnings)
    end

    describe "когда авторизации в описании нет" do
      subject(:result) { build_service("nordbank") }

      it "говорит об этом прямо, а не выдумывает заголовок" do
        expect(guide).to include("нет `securitySchemes`")
      end
    end
  end

  describe "под другим контрактом" do
    subject(:result) { build_service("novapay", contract: "plain_client") }

    it "называет файлы по-своему" do
      expect(result.files.keys)
        .to eq(%w[novapay_client.rb INTEGRATION.md fixtures.json mapping.yml])
    end

    it "называет разделы фикстур своими ролями" do
      expect(fixtures.keys).to include("send_payout", "payout_state")
    end

    it "ожидает в уведомлении статус своего словаря" do
      expect(fixtures.dig("callbacks", "payout.completed", "expected_operation_status"))
        .to eq("paid")
    end

    it "описывает свой способ отказа" do
      expect(guide).to include("ProviderError")
    end
  end
end
