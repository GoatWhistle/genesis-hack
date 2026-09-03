# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Classify::Roles do
  subject(:roles) { described_class.default }

  it "берёт весь список ролей из словаря" do
    expect(roles.ids).to contain_exactly(
      :create_payout, :fetch_status, :cancel, :refund, :balance, :webhook
    )
  end

  it "знает название роли человеческими словами" do
    expect(roles.title(:balance)).to eq("баланс")
  end

  # Главное свойство реестра: новая роль появляется правкой словаря. Если этот
  # тест начнёт падать, значит роли переехали в код и универсальность потеряна.
  it "принимает новую роль без единой правки кода" do
    extended = described_class.new(
      "payout_limits" => { "title" => "лимиты", "strong" => %w[limit] }
    )

    expect(extended.ids).to eq([:payout_limits])
  end

  it "говорит прямо, если словарь ролей пуст" do
    expect { described_class.new({}) }.to raise_error(Rsocket::Error, /словарь ролей пуст/)
  end
end
