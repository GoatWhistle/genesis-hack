# frozen_string_literal: true

require "fileutils"
require "json"
require "rack/mock_request"

RSpec.describe Controller::Http::Api do
  subject(:http) { Rack::MockRequest.new(api) }

  # Правила настоящие, результат — во временный каталог.
  let(:catalog) { Config::Catalog.new }
  let(:output) { Pathname.new(Dir.mktmpdir) }
  let(:spec_text) { File.read(example_spec("novapay")) }
  let(:api) do
    described_class.new(
      library: Service::BuildManager::Library.new(catalog: catalog),
      assembler: Service::BuildManager::Assembler.new(
        catalog: catalog, uploader: Adapter::Upload::File.new(root: output),
        spec_source: Adapter::Loader::Text::SpecReader.new
      )
    )
  end

  def body_of(response) = JSON.parse(response.body)

  describe "GET /health" do
    subject(:response) { http.get("/health") }

    it "отвечает, что жив" do
      expect(body_of(response)).to include("status" => "ok")
    end

    it "перечисляет доступные профили" do
      expect(body_of(response).fetch("contracts")).to include("space_payments", "plain_client")
    end
  end

  describe "GET /" do
    it "рассказывает о себе: по корню видно, что умеет сервис" do
      expect(body_of(http.get("/")).fetch("endpoints"))
        .to include("GET /health", "POST /build")
    end

    # Список способов есть не везде: клиент узнаёт его у сервера.
    it "называет, чем умеет раздавать роли" do
      expect(body_of(http.get("/")).fetch("classifiers")).to include("rules")
    end
  end

  describe "GET /contracts" do
    subject(:profile) do
      body_of(http.get("/contracts")).fetch("contracts")
                                     .find { |item| item["name"] == "space_payments" }
    end

    it "называет профиль и помечает используемый по умолчанию" do
      expect(profile).to include("title" => a_string_including("Space Payments"), "default" => true)
    end

    it "показывает, какие файлы профиль печатает" do
      expect(profile.fetch("outputs"))
        .to eq(%w[<provider>_service.rb INTEGRATION.md fixtures.json])
    end

    it "показывает, из чего профиль состоит в хранилище" do
      expect(profile.fetch("files"))
        .to eq(%w[contract.yml fixtures.json.erb integration.md.erb probe.rb service.rb.erb])
    end

    it "перечисляет роли с признаками и порогами" do
      expect(profile.fetch("roles").first)
        .to include("name" => "create_request", "threshold" => 13, "required" => true,
                    "traits" => %w[calls_provider creates_operation])
    end
  end

  describe "GET /openapi.yaml" do
    subject(:response) { http.get("/openapi.yaml") }

    it "отдаёт описание самого себя" do
      expect(response.body).to include("openapi: 3.0.3", "/build:")
    end

    it "отдаёт его как YAML, а не как JSON" do
      expect(response.headers["content-type"]).to include("yaml")
    end
  end

  describe "POST /build" do
    subject(:response) { http.post("/build?provider=novapay", input: spec_text) }

    it "отвечает успехом" do
      expect(response.status).to eq(200)
    end

    it "отдаёт те же файлы, что и командная строка" do
      expect(body_of(response).fetch("files").keys)
        .to eq(%w[novapay_service.rb INTEGRATION.md fixtures.json mapping.yml])
    end

    it "отдаёт готовый исходник, а не путь к нему" do
      expect(body_of(response).dig("files", "novapay_service.rb"))
        .to include("class NovapayService < BaseService")
    end

    it "кладёт рядом отчёт о разборе" do
      expect(body_of(response).dig("report", "roles", "create_request"))
        .to include("endpoint" => "POST /payouts")
    end

    it "не прячет предупреждений" do
      expect(body_of(response).fetch("warnings")).not_to be_empty
    end

    it "говорит, куда сложило результат" do
      expect(body_of(response).fetch("locations"))
        .to include(a_string_ending_with("novapay/novapay_service.rb"))
    end

    it "действительно складывает файлы в хранилище результата" do
      response
      expect(output.join("novapay", "novapay_service.rb")).to exist
    end

    # Curl без Content-Type шлёт форму: параметры берём только из строки запроса.
    it "читает описание из тела, даже если клиент назвал его формой" do
      form = "application/x-www-form-urlencoded"
      response = http.post("/build?provider=novapay", input: spec_text, "CONTENT_TYPE" => form)
      expect(response.status).to eq(200)
    end

    it "принимает описание в JSON" do
      as_json = JSON.generate(YAML.safe_load(spec_text, aliases: true))
      expect(http.post("/build?provider=novapay", input: as_json).status).to eq(200)
    end

    # Проверка исполняет напечатанный код, поэтому по HTTP её просят явно.
    describe "когда просят проверить собранное" do
      subject(:checks) do
        body_of(http.post("/build?provider=novapay&test=1", input: spec_text)).fetch("checks")
      end

      it "дёргает собранный сервис и отчитывается, что сошлось" do
        expect(checks).to include("failed" => 0, "passed" => a_value > 0)
      end

      it "кладёт тот же итог в отчёт, который уходит заказчику" do
        expect(checks).to eq(body_of(http.post("/build?provider=novapay&test=1", input: spec_text))
                               .dig("report", "checks"))
      end
    end

    it "без просьбы ничего не исполняет" do
      expect(body_of(response)).not_to have_key("checks")
    end

    describe "когда просят другой контракт" do
      subject(:response) do
        http.post("/build?provider=novapay&contract=plain_client", input: spec_text)
      end

      it "собирает под него" do
        expect(body_of(response).fetch("files").keys).to include("novapay_client.rb")
      end
    end
  end

  describe "ошибки" do
    it "просит имя провайдера, если его не передали" do
      response = http.post("/build", input: spec_text)
      expect(response).to have_attributes(status: 400, body: /обязательный параметр provider/)
    end

    it "говорит о пустом теле, а не падает" do
      response = http.post("/build?provider=novapay", input: "")
      expect(response).to have_attributes(status: 400, body: /описание API пустое/)
    end

    it "объясняет, что описание не разобралось" do
      response = http.post("/build?provider=novapay", input: "{ не json")
      expect(response).to have_attributes(status: 400, body: /не разобрать/)
    end

    it "перечисляет известные профили, если запрошен неизвестный" do
      response = http.post("/build?provider=novapay&contract=missing", input: spec_text)
      expect(response).to have_attributes(status: 400, body: /контракт не найден/)
    end

    # Негодное описание — это 422, а не поломка сервера.
    it "отвечает 422, когда обязательные роли не распознались" do
      response = http.post("/build?provider=novapay", input: "openapi: 3.0.0\npaths: {}\n")
      expect(response).to have_attributes(status: 422, body: /не распознаны обязательные роли/)
    end

    it "на неизвестную ручку отвечает списком известных" do
      response = http.get("/nope")
      expect(response).to have_attributes(status: 404, body: %r{POST /build})
    end
  end

  # Правила правятся через API; хранилище здесь временное.
  describe "менеджер правил" do
    let(:catalog) { Config::Catalog.new(store: store) }
    let(:store) do
      root = Pathname.new(Dir.mktmpdir)
      FileUtils.cp_r(Pathname.new("app/config/rules").children, root)
      Repositories::Rules::Local.new(root: root)
    end

    it "перечисляет, что лежит в хранилище" do
      keys = body_of(http.get("/rules")).fetch("files").map { |item| item["key"] }
      expect(keys).to include("base.yml", "contracts/space_payments/contract.yml")
    end

    it "отличает правила от шаблонов интерфейса" do
      files = body_of(http.get("/rules")).fetch("files")
      expect(files.find { |item| item["key"].end_with?(".erb") }).to include("kind" => "template")
    end

    it "показывает только запрошенную часть" do
      keys = body_of(http.get("/rules?prefix=contracts/plain_client/"))
             .fetch("files").map { |item| item["key"] }
      expect(keys).to all(start_with("contracts/plain_client/"))
    end

    it "отдаёт содержимое файла" do
      expect(body_of(http.get("/rules/base.yml")).fetch("content")).to include("archetypes:")
    end

    it "объясняет, если файла нет" do
      expect(http.get("/rules/missing.yml")).to have_attributes(status: 400, body: /не найдено/)
    end

    it "не пускает ключ странного вида" do
      expect(http.get("/rules/.ssh/id_rsa")).to have_attributes(status: 400,
                                                                body: /недопустимый ключ/)
    end

    it "принимает правила телом запроса" do
      response = http.put("/rules/contracts/space_payments/contract.yml",
                          input: store.read("contracts/space_payments/contract.yml"))
      expect(body_of(response).fetch("saved")).to include("kind" => "rules")
    end

    it "принимает шаблон интерфейса и запоминает его" do
      http.put("/rules/contracts/space_payments/service.rb.erb", input: "# новый шаблон\n")
      expect(store.read("contracts/space_payments/service.rb.erb")).to eq("# новый шаблон\n")
    end

    # Испорченные правила иначе свалили бы не запись, а следующую сборку.
    it "не даёт записать сломанный YAML" do
      response = http.put("/rules/base.yml", input: "archetypes: [\n")
      expect(response).to have_attributes(status: 400, body: /не разобрать YAML/)
    end

    it "не даёт записать пустоту" do
      expect(http.put("/rules/base.yml", input: "  ")).to have_attributes(status: 400)
    end

    it "не выпускает запись за пределы хранилища" do
      response = http.put("/rules/../../etc/passwd", input: "нет")
      expect(response.status).to eq(400)
    end

    it "собирает по правилам из этого же хранилища" do
      response = http.post("/build?provider=novapay", input: spec_text)
      expect(response.status).to eq(200)
    end

    # Новый профиль появляется простой записью его файлов — отдельной команды нет.
    it "видит профиль, записанный через API" do
      copy_profile("copy")
      expect(body_of(http.get("/health")).fetch("contracts")).to include("copy")
    end

    # Новый профиль — это просто набор записанных файлов.
    def copy_profile(name)
      %w[contract.yml service.rb.erb integration.md.erb fixtures.json.erb].each do |file|
        http.put("/rules/contracts/#{name}/#{file}",
                 input: store.read("contracts/space_payments/#{file}"))
      end
    end
  end
end
