# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Classification::Classifier do
  subject(:bindings) { described_class.new(rules).call(operations_for(provider)) }

  # Описания в examples/ зовут одно и то же разными словами.
  {
    "novapay" => { create_request: "create_payout", fetch_status: "get_payout_status",
                   process_callback: "payout_webhook", cancel_request: "cancel_payout" },
    "swiftpay" => { create_request: "submit_transfer", fetch_status: "fetch_transfer",
                    process_callback: "transfer_state_callback",
                    cancel_request: "revoke_transfer" },
    "kassabox" => { create_request: "make_transfer", fetch_status: "transfer_info",
                    process_callback: "transfer_notification",
                    cancel_request: "abort_transfer" },
    "nordbank" => { create_request: "create_payment_order", fetch_status: "get_payment_order",
                    process_callback: "payment_order_notification",
                    cancel_request: "revoke_payment_order" },
    # Бедное описание из spec/fixtures: уведомлений в нём нет, и роль обязана
    # остаться незанятой, а не достаться ближайшей похожей операции.
    "plainpay" => { create_request: "create_payout", fetch_status: "get_payout_status",
                    process_callback: nil, cancel_request: nil }
  }.each do |example_name, expected|
    describe "на описании #{example_name}" do
      let(:provider) { example_name }

      expected.each do |role, method_name|
        if method_name
          it "отдаёт роли #{role} операцию #{method_name}" do
            expect(bindings.fetch(role).operation.method_name).to eq(method_name)
          end
        else
          it "оставляет роль #{role} без операции" do
            expect(bindings.fetch(role)).not_to be_bound
          end
        end
      end
    end
  end

  describe "на описании novapay" do
    let(:provider) { "novapay" }

    it "не отдаёт балансу ни одной роли" do
      expect(bindings.values.select(&:bound?).map { |binding| binding.operation.method_name })
        .not_to include("get_balance")
    end

    it "объясняет решение сработавшими правилами" do
      expect(bindings.fetch(:create_request).explanation).to include("счёт", "при пороге")
    end

    it "не отдаёт одну операцию двум ролям" do
      claimed = bindings.values.select(&:bound?).map(&:operation)
      expect(claimed.uniq.size).to eq(claimed.size)
    end
  end

  describe "когда возврат средств похож на создание выплаты" do
    let(:provider) { "kassabox" }

    it "снимает возврат с роли создания" do
      expect(bindings.fetch(:create_request).operation.method_name).not_to eq("issue_refund")
    end
  end
end
