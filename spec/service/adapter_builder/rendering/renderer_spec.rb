# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Rendering::Renderer do
  EXAMPLES.each do |reference|
    describe "на описании #{File.basename(File.dirname(reference))}" do
      subject(:source) { build_service(provider).source }

      let(:provider) { File.basename(File.dirname(reference)) }
      # Четыре метода контракта заказчика: класс без любого из них бесполезен.
      let(:contract) { %w[check_conditions create_request process_callback fetch_status] }

      it "печатает синтаксически верный Ruby" do
        expect { RubyVM::InstructionSequence.compile(source) }.not_to raise_error
      end

      it "печатает все методы контракта" do
        expect(source.scan(/def (\w+)/).flatten).to include(*contract)
      end

      it "наследуется от BaseService" do
        expect(source).to match(/class \w+Service < BaseService/)
      end

      it "берёт адрес провайдера из окружения" do
        expect(source).to include(%(ENV_PREFIX = "#{provider.upcase}"), "BASE_URL = ENV.fetch(")
      end

      it "обходится стандартной библиотекой: сервису не нужен ни клиент, ни гемы" do
        expect(source.scan(/^require "(.+)"/).flatten)
          .to contain_exactly("json", "net/http", "openssl", "uri")
      end
    end
  end

  describe "когда провайдер требует ключ в заголовке" do
    subject(:source) { build_service("novapay").source }

    it "подписывает запрос тем заголовком, который назвал провайдер" do
      expect(source).to include('message["X-API-Key"] = credential(:api_key)')
    end
  end

  describe "когда провайдер требует bearer-токен" do
    subject(:source) { build_service("swiftpay").source }

    it "собирает заголовок авторизации из токена" do
      expect(source)
        .to include("message[\"Authorization\"] = \"Bearer \#{credential(:access_token)}\"")
    end
  end

  describe "когда авторизации в описании нет" do
    subject(:source) { build_service("nordbank").source }

    it "оставляет пустой authorize с TODO, а не выдуманный заголовок" do
      expect(source).to include("# TODO: в описании нет securitySchemes")
    end
  end

  describe "когда webhook описан" do
    subject(:source) { build_service("novapay").source }

    it "проверяет подпись до разбора события" do
      expect(source.index("valid_signature?")).to be < source.index("callback_status")
    end

    it "разводит события по методам контракта" do
      expect(source).to include("approve_operation(operation_id)", "reject_operation(operation_id")
    end

    it "берёт алгоритм подписи из описания" do
      expect(source).to include('SIGNATURE_ALGORITHM = "sha256"')
    end
  end

  describe "когда webhook не описан" do
    subject(:source) { build_service("plainpay").source }

    it "оставляет заглушку вместо выдуманного разбора" do
      expect(source).to include('failure(:not_implemented, "provider.callback_not_supported")')
    end

    it "объясняет в комментарии, почему заглушка" do
      expect(source).to include("Webhook не найден")
    end

    it "всё равно печатает метод контракта" do
      expect(source).to include("def process_callback(_payload)")
    end
  end

  describe "когда имена полей провайдера в верблюжьем регистре" do
    subject(:source) { build_service("kassabox").source }

    it "оставляет их без переименования" do
      expect(source).to include("orderNo:", "cardToken:")
    end

    it "читает ответ теми же именами, какими их назвал провайдер" do
      expect(source).to include('dig_body(response.body, "data", "transferNo")')
    end
  end
end
