# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Parsing::SpecParser do
  subject(:spec) { described_class.new(document).call }

  describe "на обычном OpenAPI 3.0 (регрессия)" do
    subject(:operation) { spec.operations.first }

    let(:document) do
      {
        openapi: "3.0.0",
        info: { title: "Novapay", version: "1.0.0" },
        servers: [{ url: "https://api.novapay.test" }],
        components: {
          securitySchemes: { ApiKeyAuth: { type: "apiKey", in: "header", name: "X-Api-Key" } },
          schemas: { Payout: { type: "object", properties: { id: { type: "string" } } } }
        },
        paths: {
          "/payouts" => {
            post: {
              operationId: "createPayout",
              requestBody: { content: { "application/json": {
                schema: { "$ref": "#/components/schemas/Payout" }
              } } },
              responses: { "200": { description: "ok", content: { "application/json": {
                schema: { "$ref": "#/components/schemas/Payout" }
              } } } }
            }
          }
        }
      }
    end

    it "разбирает имя операции" do
      expect(operation.method_name).to eq("create_payout")
    end

    it "раскрывает $ref в схеме запроса" do
      expect(operation.request_schema).to include(type: "object")
    end

    it "помечает операцию из paths как исходящую" do
      expect(operation.incoming).to be(false)
    end

    it "собирает схемы в Models::ApiSpec#schemas" do
      expect(spec.schemas).to have_key(:Payout)
    end

    it "распознаёт авторизацию по api-ключу" do
      expect(spec.security_schemes.first.credential_kind).to eq(:api_key)
    end
  end

  describe "на Swagger 2.0" do
    subject(:operation) { spec.operations.first }

    let(:document) do
      {
        swagger: "2.0",
        info: { title: "Qualpay", version: "1.0.0" },
        host: "api-test.qualpay.test",
        basePath: "/pg",
        schemes: ["https"],
        securityDefinitions: { basicAuth: { type: "basic" } },
        definitions: {
          CardRequest: { type: "object", properties: { pan: { type: "string" } } }
        },
        paths: {
          "/card" => {
            post: {
              operationId: "createCard",
              consumes: ["application/json"],
              produces: ["application/json"],
              parameters: [
                { name: "body", in: "body", required: true,
                  schema: { "$ref": "#/definitions/CardRequest" } },
                { name: "count", in: "query", required: false, type: "integer" }
              ],
              responses: {
                "200" => { description: "ok", schema: { "$ref": "#/definitions/CardRequest" } }
              }
            }
          }
        }
      }
    end

    it "переносит тело из in: body в схему запроса" do
      expect(operation.request_schema).to include(type: "object")
    end

    it "раскрывает $ref на definitions внутри тела запроса" do
      expect(operation.request_schema.dig(:properties, :pan)).to include(type: "string")
    end

    it "оставляет параметр не-body с его именем" do
      expect(operation.query_parameters.first[:name]).to eq("count")
    end

    it "собирает параметру не-body схему из плоского типа" do
      expect(operation.query_parameters.first[:schema]).to include(type: "integer")
    end

    it "раскрывает $ref на definitions в ответе" do
      expect(operation.success_response[:schema]).to include(type: "object")
    end

    it "строит сервер из schemes+host+basePath" do
      expect(spec.base_url).to eq("https://api-test.qualpay.test/pg")
    end

    it "кладёт definitions в Models::ApiSpec#schemas" do
      expect(spec.schemas).to have_key(:CardRequest)
    end

    it "приводит basic из securityDefinitions к схеме, понятной остальному коду" do
      expect(spec.security_schemes.first.credential_kind).to eq(:basic)
    end
  end

  describe "на входящих webhooks OpenAPI 3.1" do
    subject(:by_id) { spec.operations.group_by(&:operation_id).transform_values(&:first) }

    let(:document) do
      {
        openapi: "3.1.0",
        info: { title: "Trustly", version: "1.0.0" },
        paths: {
          "/payouts" => { post: { operationId: "createPayout", responses: {} } }
        },
        webhooks: {
          "payment.completed" => {
            post: {
              operationId: "paymentCompleted",
              requestBody: { content: { "application/json": { schema: { type: "object" } } } },
              responses: { "200": { description: "ok" } }
            }
          }
        }
      }
    end

    it "помечает операцию из webhooks как входящую" do
      expect(by_id["paymentCompleted"].incoming).to be(true)
    end

    it "оставляет операцию из paths исходящей" do
      expect(by_id["createPayout"].incoming).to be(false)
    end

    it "использует имя события как имя операции, если operationId не назван" do
      document[:webhooks]["payment.completed"][:post].delete(:operationId)

      webhook = spec.operations.find(&:incoming)
      expect(webhook.method_name).to eq("payment_completed")
    end
  end

  describe "на callbacks операции OpenAPI 3.x" do
    subject(:callback) do
      spec.operations.find { |op| op.operation_id == "payoutStatusCallback" }
    end

    let(:document) do
      {
        openapi: "3.0.3",
        info: { title: "WithCallback", version: "1.0.0" },
        paths: {
          "/payouts" => {
            post: {
              operationId: "createPayout",
              responses: {},
              callbacks: { onStatus: { "{$request.body#/callbackUrl}" => {
                post: { operationId: "payoutStatusCallback", responses: {} }
              } } }
            }
          }
        }
      }
    end

    it "разбирает callback как отдельную операцию" do
      expect(callback).not_to be_nil
    end

    it "помечает callback как входящую операцию" do
      expect(callback.incoming).to be(true)
    end
  end

  describe "диагностика неподдержанных документов" do
    it "называет причину, когда документ не OpenAPI/Swagger" do
      expect { described_class.new({ foo: "bar" }).call }
        .to raise_error(ArgumentError, %r{не OpenAPI/Swagger})
    end

    it "называет причину, когда версия OpenAPI не поддержана" do
      document = { openapi: "2.0", paths: { "/x" => { get: { responses: {} } } } }
      expect { described_class.new(document).call }
        .to raise_error(ArgumentError, /версия не поддержана/)
    end

    it "не роняет разбор молча, когда нет ни paths, ни webhooks" do
      document = { openapi: "3.0.0", info: { title: "Пусто" } }
      expect { described_class.new(document).call }
        .to raise_error(ArgumentError, /ни paths, ни webhooks/)
    end
  end
end
