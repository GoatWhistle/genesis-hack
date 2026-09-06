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
    def operation(id, method: :post, path: "/", summary: nil, incoming: false, responses: {})
      Models::ApiOperation.new(operation_id: id, http_method: method, path: path,
                               summary: summary, incoming: incoming, responses: responses)
    end

    # @return [Hash] ответ 200 со схемой из перечисленных свойств
    def answer(*names)
      { "200" => { description: "", schema: { properties: names.to_h { |n| [n, {}] } } } }
    end

    # @return [Models::RoleBinding] привязка роли на этом наборе операций
    def bind(operations, role)
      described_class.new(rules).call(operations).fetch(role)
    end

    let(:create_payout) do
      operation("createPayout", path: "/payouts", summary: "Create a payout",
                                responses: answer(:id, :status))
    end

    let(:tricky_names) do
      [operation("createTransfer", path: "/transfer", summary: "Move money between your accounts"),
       operation("createPaymentDraft", path: "/payment-drafts", summary: "Create a payment draft"),
       operation("createPayment", path: "/pay", summary: "Create a transfer to another account")]
    end

    let(:webhook_pair) do
      [operation("retryWebhook", path: "/webhooks/{id}/retry", summary: "Retry a webhook"),
       operation("payoutSettled", path: "/payout-settled", incoming: true,
                                  summary: "Payout settled notification")]
    end

    it "предпочитает исходящую выплату внутреннему переводу и черновику" do
      expect(bind(tricky_names, :create_request).operation.method_name).to eq("create_payment")
    end

    it "считает перевод на внешнюю карту выплатой" do
      card = operation("createExternalCardTransfer", path: "/external_cards/transfers",
                                                     summary: "Create External Card Transfer")

      expect(bind([card], :create_request).operation.method_name)
        .to eq("create_external_card_transfer")
    end

    it "распознаёт исходящую ACH-транзакцию и не берёт внутреннюю проводку" do
      operations = [
        operation("createBookTransfer", path: "/book_transfers", summary: "Create book transfer"),
        operation("addTransactionOut", path: "/ach", summary: "Send an ACH")
      ]

      expect(bind(operations, :create_request).operation.method_name).to eq("add_transaction_out")
    end

    it "не считает merchant order исходящей выплатой" do
      operations = [operation("createOrder", path: "/api/createOrder",
                                             summary: "Create merchant order")]

      expect(bind(operations, :create_request)).not_to be_bound
    end

    it "считает PUT и PATCH допустимыми методами отмены" do
      cancel = operation("cancelPayoutTransaction", method: :put,
                                                    path: "/payouts/{id}/cancel",
                                                    summary: "Cancel a payout transaction")

      expect(bind([create_payout, cancel], :cancel_request).operation.method_name)
        .to eq("cancel_payout_transaction")
    end

    it "берёт статус, запрошенный методом POST по соседнему адресу" do
      create = operation("createPayout", path: "/payouts/create", summary: "Create a payout",
                                         responses: answer(:id, :status))
      status = operation("getPayout", path: "/payouts/get", summary: "Get payout status",
                                      responses: answer(:id, :status, :amount))

      expect(bind([create, status], :fetch_status).operation.method_name).to eq("get_payout")
    end

    it "не берёт в статус операцию, не связанную с созданием выплаты" do
      other = operation("getSettlementBatch", method: :get, path: "/settlements/batches/{id}",
                                              summary: "Get settlement batch")

      expect(bind([create_payout, other], :fetch_status)).not_to be_bound
    end

    it "объясняет отказ статуса недоказанной связью" do
      other = operation("getSettlementBatch", method: :get, path: "/settlements/batches/{id}",
                                              summary: "Get settlement batch")

      expect(bind([create_payout, other], :fetch_status).explanation)
        .to include("связь с созданием не подтверждена")
    end

    it "не назначает ролей, когда создание выплаты не распознано" do
      operations = [
        operation("getInvoice", method: :get, path: "/invoices/{id}", summary: "Get invoice"),
        operation("cancelInvoice", path: "/invoices/{id}/cancel", summary: "Cancel invoice")
      ]

      expect(described_class.new(rules).call(operations).values.select(&:bound?)).to be_empty
    end

    it "берёт входящее уведомление из раздела webhooks, а не управление вебхуками" do
      expect(bind([create_payout, *webhook_pair], :process_callback).operation.method_name)
        .to eq("payout_settled")
    end

    it "называет соперников, когда счёт кандидатов совпал" do
      twin = operation("createPayoutTwin", path: "/payouts-twin", summary: "Create a payout",
                                           responses: answer(:id, :status))

      expect(bind([create_payout, twin], :create_request).explanation).to include("неоднозначно")
    end
  end
end
