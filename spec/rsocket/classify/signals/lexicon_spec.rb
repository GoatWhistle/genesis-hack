# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::Signals::Lexicon do
  subject(:signal) { described_class.new(context) }

  let(:dictionaries) { Rsocket::Dictionaries.default }
  let(:roles) { Rsocket::Classify::Roles.default(dictionaries) }
  let(:context) do
    Rsocket::Classify::Context.new(spec: nil, dictionaries: dictionaries, roles: roles)
  end

  def ir(name)
    path = File.join(Rsocket.root, "examples", name, "provider_api.yaml")
    Rsocket::Spec::Normalizer.normalize(Rsocket::Spec::Loader.load(path))
  end

  def operation(name, operation_id)
    ir(name).operations.find { |item| item.operation_id == operation_id }
  end

  def score(operation, role_id)
    signal.evidence(operation, roles[role_id]).sum(&:weight).round(2)
  end

  it "объясняет находку словами, а не числом" do
    found = signal.evidence(operation("novapay", "createPayout"), roles[:create_payout])

    expect(found.map(&:detail)).to include(a_string_matching(/имя операции .+ содержит «create»/))
  end

  it "помечает каждую находку своим сигналом" do
    found = signal.evidence(operation("novapay", "getPayoutStatus"), roles[:fetch_status])

    expect(found.map(&:signal).uniq).to eq([:lexicon])
  end

  it "находит на понятных именах создание, статус, отмену и баланс" do
    found = {
      create_payout: "createPayout", fetch_status: "getPayoutStatus",
      cancel: "cancelPayout", balance: "getBalance"
    }.transform_values { |id| operation("novapay", id) }

    expect(found.map { |role, item| score(item, role) }).to all(be > 2.0)
  end

  # Роль не достаётся тому, кто просто упомянул слово: у возврата в KassaBox
  # имя операции начинается с issue, и по одному этому слову он мог бы сойти за
  # создание выплаты. Проверяем, что предметные слова перевешивают.
  it "не путает возврат с созданием, когда имя начинается общим глаголом" do
    refund = operation("kassabox", "issueRefund")

    expect(score(refund, :refund)).to be > score(refund, :create_payout)
  end

  it "молчит на операции, о которой словарю нечего сказать" do
    unknown = Rsocket::Ir::Operation.new(http_method: :get, path: "/ping")

    expect(signal.evidence(unknown, roles[:create_payout])).to be_empty
  end

  it "не спотыкается об операцию без имени" do
    nameless = Rsocket::Ir::Operation.new(
      http_method: :post, path: "/transfers", summary: "Отправить перевод"
    )

    expect(score(nameless, :create_payout)).to be > 0
  end
end
