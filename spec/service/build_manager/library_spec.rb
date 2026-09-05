# frozen_string_literal: true

require "fileutils"

RSpec.describe Service::BuildManager::Library do
  subject(:library) { described_class.new(catalog: Config::Catalog.new(store: store)) }

  # Пишем во временную копию правил: тесты не должны править репозиторий.
  let(:store) do
    root = Pathname.new(Dir.mktmpdir)
    FileUtils.cp_r(Pathname.new("app/config/rules").children, root)
    Repositories::Rules::Local.new(root: root)
  end

  describe "что лежит в хранилище" do
    it "перечисляет правила и шаблоны" do
      expect(library.entries.map { |item| item[:key] })
        .to include("base.yml", "contracts/space_payments/service.rb.erb")
    end

    it "отличает правила от шаблонов интерфейса" do
      kinds = library.entries.to_h { |item| [item[:key], item[:kind]] }
      expect(kinds).to include("base.yml" => "rules",
                               "contracts/space_payments/service.rb.erb" => "template")
    end

    it "показывает только запрошенную часть" do
      keys = library.entries("contracts/plain_client/").map { |item| item[:key] }
      expect(keys).to all(start_with("contracts/plain_client/"))
    end

    it "отдаёт содержимое" do
      expect(library.read("base.yml")).to include("archetypes:")
    end
  end

  describe "правка" do
    it "записывает шаблон интерфейса" do
      library.save("contracts/space_payments/service.rb.erb", "# другой шаблон\n")
      expect(store.read("contracts/space_payments/service.rb.erb")).to eq("# другой шаблон\n")
    end

    it "рассказывает, что записала" do
      template = "# шаблон\n"
      expect(library.save("contracts/space_payments/service.rb.erb", template))
        .to include(kind: "template", bytes: template.bytesize)
    end

    # Испорченные правила иначе свалили бы не запись, а следующую сборку — и
    # разбираться пришлось бы уже другому человеку.
    it "не принимает сломанный YAML" do
      expect { library.save("base.yml", "archetypes: [\n") }
        .to raise_error(ArgumentError, /не разобрать YAML/)
    end

    it "не принимает пустоту" do
      expect { library.save("base.yml", "   ") }
        .to raise_error(ArgumentError, /пустое содержимое/)
    end

    it "не выпускает запись за пределы хранилища" do
      expect { library.save("contracts/../escape.yml", "нет: нет\n") }
        .to raise_error(ArgumentError, /за пределы хранилища/)
    end
  end

  describe "профили контрактов" do
    it "перечисляет их" do
      expect(library.names).to contain_exactly("plain_client", "space_payments")
    end

    it "показывает, из чего профиль состоит и что печатает" do
      expect(library.profile("space_payments"))
        .to include(title: a_string_including("Space Payments"), default: true,
                    files: %w[contract.yml fixtures.json.erb integration.md.erb service.rb.erb],
                    outputs: %w[<provider>_service.rb INTEGRATION.md fixtures.json])
    end

    it "показывает роли с признаками" do
      roles = library.profile("space_payments").fetch(:roles)
      expect(roles.first).to include(name: :create_request, required: true,
                                     traits: %i[calls_provider creates_operation])
    end

    # Новый профиль появляется простой записью файлов: отдельной команды нет.
    it "видит профиль, записанный через неё же" do
      %w[contract.yml service.rb.erb integration.md.erb fixtures.json.erb].each do |file|
        library.save("contracts/copy/#{file}", store.read("contracts/space_payments/#{file}"))
      end
      expect(library.names).to include("copy")
    end
  end
end
