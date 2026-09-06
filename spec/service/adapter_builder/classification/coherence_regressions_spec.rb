# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Classification::Coherence do
  def operation(path, id = "payout")
    schema = { properties: { id: {}, status: {}, amount: {} } }
    Models::ApiOperation.new(operation_id: id, http_method: :post, path: path,
                             responses: { "200" => { schema: schema } })
  end

  [
    ["/accounts/{account_id}/transfers", "/accounts/{account_id}"],
    ["/payouts/batches", "/payouts/{id}"],
    ["/payments/ach", "/payments/wires/{id}"],
    ["/payouts", "/payouts/{id}/refunds"],
    ["/payouts/{id}/payments", "/payouts/payments/{id}"],
    ["/accounts/{id}/transfers", "/accounts/{id}/transfers/{id}/beneficiaries"],
    ["/payments/ach", "/payments/wires/{id}/cancellations"],
    ["/payments/ach", "/payments/ach/wire-status"],
    ["/payouts", "/payouts-item/{id}/cancel"],
    ["/batches/{batchId}/transfers", "/batches/{batchId}/cancel"],
    ["/v1/{service}/{product}", "/v1/{service}"],
    ["/v1/{service}/{product}", "/v1/{service}/{product}/{id}/refunds"]
  ].each do |create, other|
    it "rejects distinct resources #{create} and #{other} despite shared schemas and IDs" do
      expect(described_class).not_to be_linked(operation(create), operation(other))
    end
  end

  [
    ["/payments", "/payments/{id}"],
    ["/payments/create", "/payments/get"],
    ["/accounts/{account_id}/transfers", "/accounts/{account_id}/transfers/{id}/cancel"],
    ["/disbursements", "/disbursements/{reference}/halt"],
    ["/accounts/{account_id}/transfers", "/accounts/{account_id}/transfers/{id}/cancellations"],
    ["/payments/credit-transfers", "/payments/credit-transfers/payment-status"],
    ["/v1/{service}/{product}", "/v1/{service}/{product}/{id}"],
    ["/v1/{service}/{product}", "/v1/{service}/{product}/{id}/status"]
  ].each do |create, other|
    it "links the same resource #{create} and #{other}" do
      expect(described_class).to be_linked(operation(create), operation(other))
    end
  end

  describe "local bench operations" do
    def bench_operations(path)
      file = File.expand_path("../../../../#{path}", __dir__)
      skip "local bench spec unavailable: #{path}" unless File.file?(file)

      document = Adapter::Loader::File::SpecLoader.new.read(file)
      operations = Service::AdapterBuilder::Parsing::SpecParser.new(document).call.operations
      operations.to_h { |op| [op.method_name, op] }
    end

    [
      ["bench/unseen/provider_api.yaml", "enqueue_disbursement", "halt_disbursement", true],
      ["bench/specs/paypal-payouts-v1.json", "payouts_post", "payouts_item_cancel", false],
      ["bench/specs/fire-com.json", "add_bank_transfer_batch_payment",
       "get_details_single_batch", false],
      ["bench/specs/fire-com.json", "add_bank_transfer_batch_payment",
       "cancel_batch_payment", false],
      ["bench/specs/fire-com.json", "add_bank_transfer_batch_payment",
       "delete_bank_transfer_batch_payment", true],
      ["bench/specs/openbanking-ch.json", "initiate_payment", "cancel_payment", true],
      ["bench/specs/openbanking-ch.json", "initiate_payment", "get_payment_information", true],
      ["bench/specs/moov.yaml", "create_transfer", "create_cancellation", true]
    ].each do |path, create, other, linked|
      it "#{linked ? "links" : "rejects"} #{create} / #{other}" do
        ops = bench_operations(path)
        expect(described_class.linked?(ops.fetch(create), ops.fetch(other))).to eq(linked)
      end
    end

    products = %w[domestic-credit-transfers sepa-credit-transfers cross-border-credit-transfers]
    products.product(products).each do |product, status_product|
      it "checks Mastercard #{product} against #{status_product} status" do
        ops = bench_operations("bench/specs-new/mastercard-ob-pis.json")
        create = ops.fetch("post_payments_#{product}")
        status = ops.fetch("post_payments_#{status_product}_payment-status")
        expect(described_class.linked?(create, status)).to eq(product == status_product)
      end
    end
  end
end
