# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Classification::Classifier do
  subject(:bindings) { described_class.new(rules).call(operations_for(provider)) }

  # Описания в examples/ зовут одно и то же разными словами.
  {
    "novapay" => { create_request: "create_payout", fetch_status: "get_payout_status",
                   process_callback: "payout_webhook", cancel_request: "cancel_payout" },
    "swiftpay" => { create_request: "submit_transfer", fetch_status: "fetch_transfer",
                    process_callback: nil, cancel_request: "revoke_transfer" },
    "kassabox" => { create_request: "make_transfer", fetch_status: "transfer_info",
                    process_callback: nil, cancel_request: "abort_transfer" },
    "nordbank" => { create_request: "create_payment_order", fetch_status: "get_payment_order",
                    process_callback: nil, cancel_request: "revoke_payment_order" }
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

  describe "на неоднозначных названиях чужих API" do
    def operation(id, method: :post, path: "/", summary: nil, tags: [])
      Models::ApiOperation.new(operation_id: id, http_method: method, path: path,
                               summary: summary, tags: tags)
    end

    it "предпочитает исходящую выплату внутреннему переводу и черновику" do
      operations = [
        operation("createTransfer", path: "/transfer",
                                    summary: "Move money between your accounts"),
        operation("createPaymentDraft", path: "/payment-drafts",
                                        summary: "Create a payment draft"),
        operation("createPayment", path: "/pay",
                                   summary: "Create a transfer to another account")
      ]

      binding = described_class.new(rules).call(operations).fetch(:create_request)

      expect(binding.operation.method_name).to eq("create_payment")
    end

    it "распознаёт исходящую ACH-транзакцию и не берёт перевод на внешнюю карту" do
      operations = [
        operation("createExternalCardTransfer", path: "/external_cards/transfers",
                                                summary: "Create External Card Transfer"),
        operation("addTransactionOut", path: "/ach", summary: "Send an ACH")
      ]

      binding = described_class.new(rules).call(operations).fetch(:create_request)

      expect(binding.operation.method_name).to eq("add_transaction_out")
    end

    it "не считает merchant order исходящей выплатой" do
      operations = [
        operation("createOrder", path: "/api/createOrder", summary: "Create merchant order")
      ]

      binding = described_class.new(rules).call(operations).fetch(:create_request)

      expect(binding).not_to be_bound
    end

    it "считает PUT и PATCH допустимыми методами отмены" do
      operations = [
        operation("createPayout", path: "/payouts", summary: "Create payout"),
        operation("cancelPayoutTransaction", method: :put,
                                              path: "/payouts/{id}/transactions/{transaction_id}/cancel",
                                              summary: "Cancel a payout transaction")
      ]

      binding = described_class.new(rules).call(operations).fetch(:cancel_request)

      expect(binding.operation.method_name).to eq("cancel_payout_transaction")
    end
  end
end
