# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Classification::Classifier do
  def operation(id, method, path, request = {})
    Models::ApiOperation.new(operation_id: id, http_method: method, path: path, request: request)
  end

  def classify(properties)
    schema = { type: "object", properties: properties.to_h { |name| [name, { type: "string" }] } }
    create = operation("createPayment", :post, "/payments", schema: schema)
    status = operation("getPayment", :get, "/payments/{id}")
    cancel = operation("cancelPayment", :post, "/payments/{id}/cancel")
    described_class.new(rules).call([create, status, cancel])
  end

  %i[delayed_capture capture_method moto prefilled_cardholder_details].each do |field|
    it "rejects checkout creation and dependent roles with return_url and #{field}" do
      expect(classify([:amount, :return_url, field]).values).to all(have_attributes(bound?: false))
    end
  end

  it "does not treat a return URL alone as evidence of incoming payment" do
    result = classify(%i[amount currency recipient return_url])
    expect(result.fetch(:create_request)).to be_bound
  end

  it "does not veto on an isolated capture field without a checkout return URL" do
    result = classify(%i[amount currency recipient capture_method])
    expect(result.fetch(:create_request)).to be_bound
  end

  it "still selects an outgoing payout in an API that also offers checkout" do
    schema = { properties: { return_url: {}, delayed_capture: {} } }
    checkout = operation("createPayment", :post, "/payments", schema: schema)
    payout = operation("createPayout", :post, "/payouts")
    result = described_class.new(rules).call([checkout, payout])
    expect(result.fetch(:create_request).operation).to equal(payout)
  end
end
