# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::Signals::Signature do
  subject(:signal) { described_class.new(classify_context(provider)) }

  let(:provider) { "kassabox" }
  let(:roles) { Rsocket::Classify::Roles.default }

  def details(provider_name, operation_id, role)
    described_class.new(classify_context(provider_name))
                   .evidence(operation(provider_name, operation_id), roles[role])
                   .map(&:detail)
  end

  # Главное свойство признака: он читает строение запроса, а не имена. На
  # KassaBox операции названы makeTransfer и transferInfo, и роли всё равно
  # находятся.
  it "узнаёт создание по сумме, валюте и получателю в теле" do
    expect(details("kassabox", "makeTransfer", :create_payout))
      .to include(a_string_matching(/сумма «sum», валюта и получатель «payee»/))
  end

  it "узнаёт запрос статуса по идентификатору в пути и статусу в ответе" do
    expect(details("kassabox", "transferInfo", :fetch_status))
      .to include(a_string_matching(/идентификатором в пути «transferNo».+«data\.state»/))
  end

  it "узнаёт отмену по пустому телу на адресе созданного ресурса" do
    expect(details("kassabox", "abortTransfer", :cancel))
      .to include(a_string_matching(/пустым телом запроса/))
  end

  it "узнаёт возврат по ссылке на исходную операцию без получателя" do
    expect(details("kassabox", "issueRefund", :refund))
      .to include(a_string_matching(/ссылка на ранее созданную операцию «transferNo»/))
  end

  it "узнаёт баланс по сумме и валюте в ответе без параметров" do
    expect(details("novapay", "getBalance", :balance))
      .to include(a_string_matching(/GET без параметров/))
  end

  it "узнаёт приём уведомлений по открытому методу с событием и статусом" do
    expect(details("novapay", "payoutWebhook", :webhook))
      .to include(a_string_matching(/объявлен открытым/))
  end

  # Возврат тоже POST с суммой, и без проверки получателя он сошёл бы за
  # создание выплаты.
  it "не считает созданием то, где нет получателя" do
    expect(details("kassabox", "issueRefund", :create_payout)).to be_empty
  end

  it "не считает отменой чтение ресурса" do
    expect(details("kassabox", "transferInfo", :cancel)).to be_empty
  end

  it "молчит, когда роль не объявила ни одного правила" do
    role = Rsocket::Classify::Role.new(id: :new_role, title: "новая", rules: [])

    expect(signal.evidence(operation(provider, "makeTransfer"), role)).to be_empty
  end
end
