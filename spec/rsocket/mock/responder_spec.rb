# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Mock::Responder do
  subject(:responder) { described_class.new(ir_spec) }

  let(:ir_spec) do
    response = Rsocket::Ir::Response.new(
      code: 202,
      examples: { "first" => { "choice" => 1 }, "second" => { "choice" => 2 } }
    )
    operation = Rsocket::Ir::Operation.new(
      http_method: :post, path: "/things/{thing_id}", responses: { 202 => response }
    )
    Rsocket::Ir::Spec.new(operations: [operation])
  end

  it "matches templated paths and ignores the query string", :aggregate_failures do
    response = responder.call(method: "POST", path: "/things/abc?verbose=true")

    expect(response.status).to eq(202)
    expect(response.body).to eq("choice" => 1)
  end

  it "returns independent copies of examples" do
    responder.call(method: :post, path: "/things/abc").body["choice"] = 99

    expect(responder.call(method: :post, path: "/things/abc").body).to eq("choice" => 1)
  end
end
