# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::Classifier do
  # Три описания названы по-разному нарочно: если разбор смысла держится на
  # словах одного провайдера, эти проверки покраснеют.
  let(:novapay) { classify("novapay") }
  let(:swiftpay) { classify("swiftpay") }
  let(:kassabox) { classify("kassabox") }

  def ir(name)
    path = File.join(Rsocket.root, "examples", name, "provider_api.yaml")
    Rsocket::Spec::Normalizer.normalize(Rsocket::Spec::Loader.load(path))
  end

  def classify(name, **options)
    described_class.call(ir(name), **options)
  end

  # Роль → «METHOD /path»: сравнивать удобнее строки, чем объекты операций.
  def assigned(result)
    result.roles.transform_values do |item|
      "#{item.operation.http_method.to_s.upcase} #{item.operation.path}"
    end
  end

  def messages(result, level)
    result.notes.select { |note| note.level == level }.map(&:message)
  end

  it "находит роли на описании с понятными именами" do
    expect(assigned(novapay)).to include(
      create_payout: "POST /payouts", fetch_status: "GET /payouts/{payout_id}",
      cancel: "POST /payouts/{payout_id}/cancel", balance: "GET /balance",
      webhook: "POST /webhooks/payout"
    )
  end

  it "находит роли на описании с другим способом входа и без уведомлений" do
    expect(assigned(swiftpay)).to include(
      create_payout: "POST /transfers", fetch_status: "GET /transfers/{transfer_id}",
      cancel: "POST /transfers/{transfer_id}/cancel"
    )
  end

  it "находит роли на описании с непрозрачными именами операций" do
    expect(assigned(kassabox)).to include(
      create_payout: "POST /v1/transfers", fetch_status: "GET /v1/transfers/{transferNo}",
      cancel: "POST /v1/transfers/{transferNo}/abort", refund: "POST /v1/refunds"
    )
  end

  it "не назначает одну операцию на две роли" do
    operations = novapay.roles.values.map { |item| item.operation.path }

    expect(operations).to eq(operations.uniq)
  end

  it "показывает проигравшего кандидата, а не молчит о нём" do
    expect(messages(novapay, :needs_confirmation))
      .to include(a_string_matching(/претендовали две операции/))
  end

  it "честно говорит, что роли не нашлось" do
    expect(messages(swiftpay, :info))
      .to include(a_string_matching(/«приём уведомлений» не определена/))
  end

  it "объясняет каждую назначенную роль признаками" do
    expect(novapay.roles[:create_payout].evidence).not_to be_empty
  end

  it "считает оценку роли по признакам" do
    assignment = novapay.roles[:create_payout]

    expect(assignment.score).to eq(assignment.evidence.sum(&:weight).round(2))
  end

  # Одинаковый вход обязан давать одинаковый выход: нейросетей внутри нет,
  # случайности быть не должно тоже.
  it "даёт один и тот же результат на одном и том же описании" do
    expect(assigned(kassabox)).to eq(assigned(classify("kassabox")))
  end

  context "со своим словарём ролей" do
    let(:dictionaries) { Rsocket::Dictionaries.new }
    let(:single_role) { { "balance" => { "title" => "баланс", "strong" => %w[balance баланс] } } }

    before { allow(dictionaries).to receive(:operations).and_return(single_role) }

    # Реестр ролей приходит из словаря целиком: механизм оценки не знает ни
    # одной роли по имени и обязан работать на любом наборе.
    it "работает на том наборе ролей, который дал словарь" do
      expect(classify("novapay", dictionaries: dictionaries).roles.keys).to eq([:balance])
    end
  end
end
