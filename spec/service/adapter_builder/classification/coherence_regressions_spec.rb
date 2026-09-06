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
    ["/accounts/{id}/transfers", "/accounts/{id}/transfers/{id}/beneficiaries"]
  ].each do |create, other|
    it "rejects distinct resources #{create} and #{other} despite shared schemas and IDs" do
      expect(described_class).not_to be_linked(operation(create), operation(other))
    end
  end

  [
    ["/payments", "/payments/{id}"],
    ["/payments/create", "/payments/get"],
    ["/accounts/{account_id}/transfers", "/accounts/{account_id}/transfers/{id}/cancel"]
  ].each do |create, other|
    it "links the same resource #{create} and #{other}" do
      expect(described_class).to be_linked(operation(create), operation(other))
    end
  end
end
