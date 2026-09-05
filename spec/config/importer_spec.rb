# frozen_string_literal: true

RSpec.describe Config::Importer do
  subject(:settings) { described_class.call }

  it "поднимает роли в порядке разбора" do
    expect(settings.ordered_roles.map(&:name)).to eq(%i[create_request fetch_status
                                                        process_callback cancel_request])
  end

  it "компилирует правила в регулярки" do
    expect(settings.role(:create_request).rules).to all(have_attributes(pattern: a_kind_of(Regexp)))
  end

  it "даёт создание выплаты порог выше общего" do
    expect(settings.role(:create_request).threshold)
      .to be > settings.role(:cancel_request).threshold
  end

  it "требует обязательные роли" do
    expect(settings).to be_required_role(:create_request).and be_required_role(:fetch_status)
  end

  it "не считает отмену обязательной" do
    expect(settings).not_to be_required_role(:cancel_request)
  end

  it "находит ошибку по коду ответа" do
    expect(settings.error_for(429)).to include(code: "rate_limit", symbol: "too_many_requests")
  end

  it "отдаёт общее правило на незнакомый код" do
    expect(settings.error_for(418)).to include(code: "unknown_error")
  end

  it "соединяет распознавание из базы с выражением из контракта" do
    amount = settings.entry_for(settings.payload_fields, :amount)
    expect(amount).to include(patterns: all(a_kind_of(Regexp)),
                              source: "provider_amount(operation)")
  end

  # Роль ищут не по имени, а по признаку: имена у каждого контракта свои.
  it "находит роль, создающую операцию, по признаку" do
    expect(settings.role_with(:creates_operation).name).to eq(:create_request)
  end

  it "находит роль, принимающую webhook, по признаку" do
    expect(settings.role_with(:receives_callback).name).to eq(:process_callback)
  end

  it "перечисляет роли, ходящие к провайдеру, в порядке разбора" do
    expect(settings.roles_with(:calls_provider).map(&:name))
      .to eq(%i[create_request fetch_status cancel_request])
  end

  describe "когда профиля контракта нет" do
    it "падает внятно и перечисляет известные" do
      expect { described_class.call("нет") }
        .to raise_error(ArgumentError, /контракт не найден: нет\. Известны: .*space_payments/)
    end
  end

  describe "когда контракт описан с ошибкой" do
    subject(:import) { described_class.new("broken", catalog: catalog).call }

    let(:directory) { Pathname.new(Dir.mktmpdir) }
    let(:catalog) { Config::Catalog.new(store: Repositories::Rules::Local.new(root: directory)) }
    let(:contract) { directory.join("contracts", "broken", "contract.yml") }

    # Профиль подкладываем во временное хранилище целиком: правила распознавания
    # общие, ломаем только описание контракта.
    before do
      contract.dirname.mkpath
      contract.write(Pathname.new("app/config/rules/contracts/space_payments/contract.yml")
                             .read.gsub(*replacement))
      directory.join("base.yml").write(Pathname.new("app/config/rules/base.yml").read)
    end

    describe "с неизвестным признаком роли" do
      let(:replacement) { ["traits: [calls_provider, creates_operation]", "traits: [летает]"] }

      it "называет признак и перечисляет известные" do
        expect { import }.to raise_error(ArgumentError, /неизвестные признаки летает/)
      end
    end

    describe "с двумя ролями, создающими операцию" do
      let(:replacement) do
        ["traits: [calls_provider]\n    process_callback:",
         "traits: [calls_provider, creates_operation]\n    process_callback:"]
      end

      it "не даёт собрать: разбору не из чего выбирать" do
        expect { import }.to raise_error(ArgumentError, /creates_operation.*ровно одна роль/m)
      end
    end

    describe "с ролью без архетипа в базе" do
      let(:replacement) { ["archetype: creation", "archetype: телепатия"] }

      it "называет архетип и перечисляет известные" do
        expect { import }.to raise_error(ArgumentError, /неизвестный архетип телепатия/)
      end
    end
  end
end
