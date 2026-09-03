# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::Signals::Lifecycle do
  let(:roles) { Rsocket::Classify::Roles.default }

  def details(provider, operation_id, role)
    described_class.new(classify_context(provider))
                   .evidence(operation(provider, operation_id), roles[role])
                   .map(&:detail)
  end

  # Признак не читает ни одного слова провайдера: только строение адресов.
  # Поэтому он одинаково работает на всех трёх описаниях.
  it "видит создающую операцию по выданному идентификатору" do
    expect(details("novapay", "createPayout", :create_payout))
      .to include(a_string_matching(%r{идентификатор «id».+«/payouts/\{payout_id\}»}))
  end

  it "видит создающую операцию там, где ответ завёрнут в конверт" do
    expect(details("kassabox", "makeTransfer", :create_payout))
      .to include(a_string_matching(/идентификатор «data\.transferNo»/))
  end

  it "видит создающую операцию на описании с дробными суммами" do
    expect(details("swiftpay", "submitTransfer", :create_payout))
      .to include(a_string_matching(/идентификатор «transfer_id»/))
  end

  it "видит чтение состояния по идентификатору без тела запроса" do
    expect(details("swiftpay", "fetchTransfer", :fetch_status))
      .to include("ресурс читается по идентификатору и без тела запроса")
  end

  it "видит продолжение адреса созданного ресурса" do
    expect(details("kassabox", "abortTransfer", :cancel))
      .to include(a_string_matching(%r{адрес продолжает «/v1/transfers»}))
  end

  it "не приписывает создание операции, чей идентификатор никому не нужен" do
    expect(details("kassabox", "issueRefund", :create_payout)).to be_empty
  end
end
