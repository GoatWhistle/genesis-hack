# frozen_string_literal: true

require "spec_helper"
require "rsocket/generate/service_generator"

require_relative "support/classification"

# Сборка одного сервиса стоит около трёх секунд: внутри конвейера дважды
# поднимается линтер отдельным процессом. Результат для одного описания
# всегда один и тот же, поэтому он считается один раз на весь файл — иначе
# набор тестов идёт минуты вместо секунд. Проверка детерминизма кеш обходит
# намеренно: ей нужны два независимых прогона.
module GeneratedServices
  def self.fetch(provider)
    @cache ||= {}
    @cache[provider] ||= build(provider)
  end

  def self.build(provider, classification: :from_double)
    spec = Rsocket::Spec::Normalizer.normalize(
      Rsocket::Spec::Loader.load("examples/#{provider}/provider_api.yaml")
    )
    doubled = classification == :from_double ? ClassificationDouble.build(provider, spec) : nil
    Rsocket::Generate::ServiceGenerator.new(spec, classification: doubled,
                                                  provider: provider).call
  end
end

# Генератор проверяется на всех трёх описаниях сразу.
#
# Одного NovaPay мало: он и был образцом, на нём всё сойдётся по построению.
# Смысл проверки в том, что тот же шаблон переживает провайдера с
# Bearer-входом и без уведомлений и провайдера с конвертом вокруг ответа и
# непрозрачными именами операций.
RSpec.describe Rsocket::Generate::ServiceGenerator do
  def generate(provider)
    GeneratedServices.fetch(provider)
  end

  def build(provider, classification: :from_double)
    GeneratedServices.build(provider, classification: classification)
  end

  %w[novapay swiftpay kassabox].each do |provider|
    describe "описание #{provider}" do
      subject(:result) { generate(provider) }

      it "собирает файл сервиса с именем провайдера" do
        expect(result.filename).to eq("#{provider}_service.rb")
      end

      it "выдаёт синтаксически верный Ruby" do
        expect { RubyVM::AbstractSyntaxTree.parse(result.source) }.not_to raise_error
      end

      it "проходит линтер без замечаний" do
        expect(result.lint).to be_clean
      end

      it "объявляет все четыре метода контракта заказчика", :aggregate_failures do
        %w[check_conditions create_request fetch_status process_callback].each do |method|
          expect(result.source).to include("def #{method}(")
        end
      end

      it "наследует заглушку контракта заказчика" do
        expect(result.source).to match(/class \w+Service < BaseService/)
      end

      # Одинаковый вход обязан давать побайтово одинаковый выход, иначе
      # инструмент нельзя держать в CI и проверять результат сравнением.
      it "даёт побайтово тот же результат при повторном прогоне" do
        expect(build(provider).source).to eq(result.source)
      end
    end
  end

  describe "перевод статусов провайдера" do
    it "сводит статусы NovaPay к трём статусам заказчика" do
      expect(generate("novapay").context.status_map)
        .to eq("pending" => "in_progress", "processing" => "in_progress",
               "completed" => "approved", "failed" => "rejected", "cancelled" => "rejected")
    end

    it "сводит непохожие статусы SwiftPay к тем же трём" do
      expect(generate("swiftpay").context.status_map)
        .to eq("new" => "in_progress", "sent" => "in_progress",
               "paid" => "approved", "declined" => "rejected")
    end
  end

  describe "провайдер без уведомлений" do
    subject(:source) { generate("swiftpay").source }

    it "не выдумывает обработчик уведомлений" do
      expect(source).to include("provider.callbacks_not_supported")
    end

    it "не тянет проверку подписи, которой негде взяться" do
      expect(source).not_to include("valid_signature?")
    end
  end

  describe "провайдер с конвертом вокруг ответа" do
    subject(:source) { generate("kassabox").source }

    it "читает идентификатор сквозь конверт" do
      expect(source).to include("RESPONSE_ID_PATH = %w[data transferNo]")
    end

    it "читает статус сквозь конверт, хотя поле названо иначе" do
      expect(source).to include("RESPONSE_STATUS_PATH = %w[data state]")
    end

    it "собирает вложенный объект суммы" do
      expect(source).to include("value: to_minor_units(operation.amount)")
    end
  end

  describe "единицы суммы" do
    it "домножает сумму там, где провайдер ждёт копейки" do
      expect(generate("novapay").source).to include("to_minor_units(operation.amount)")
    end

    it "не трогает сумму там, где провайдер ждёт дробное число" do
      expect(generate("swiftpay").source).to include("amount: operation.amount")
    end
  end

  describe "сообщения о неоднозначном" do
    it "сообщает о полях, обязательность которых задана словами описания" do
      expect(generate("novapay").notes.join)
        .to include("recipient.bank_code")
    end

    it "сообщает о полях, которые не удалось связать с операцией" do
      expect(generate("kassabox").notes.join).to include("comment")
    end
  end

  describe "когда классификатор ничего не определил" do
    subject(:result) { build("novapay", classification: nil) }

    # Роль с вердиктом «не определено» — нормальный случай, а не сбой.
    it "не падает, а собирает файл с честными заглушками" do
      expect(result.source).to include("не определена в описании API")
    end

    it "всё равно выдаёт код, проходящий линтер" do
      expect(result.lint).to be_clean
    end
  end
end
