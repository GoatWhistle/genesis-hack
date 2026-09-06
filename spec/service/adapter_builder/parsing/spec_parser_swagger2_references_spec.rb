# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Parsing::SpecParser do
  subject(:operation) { described_class.new(document).call.operations.first }

  let(:schema) { { type: "object", properties: { id: { type: "string" } } } }
  let(:document) do
    { swagger: "2.0", definitions: { Payout: schema },
      parameters: {
        Payout: { name: "body", in: "body", schema: { "$ref": "#/definitions/Payout" } },
        Account: { name: "account_id", in: "path", required: true, type: "string" }
      },
      responses: { Payout: { description: "ok", schema: { "$ref": "#/definitions/Payout" } } },
      paths: { "/accounts/{account_id}/payouts" => {
        parameters: [{ "$ref": "#/parameters/Account" }],
        post: { parameters: [{ "$ref": "#/parameters/Payout" }],
                responses: { "200" => { "$ref": "#/responses/Payout" } } }
      } } }
  end
  let(:path) { document[:paths].values.first }

  it "normalizes a shared body parameter before resolving its definition" do
    expect(operation.request_schema).to eq(schema)
  end

  it "normalizes a shared response schema after resolving the response reference" do
    expect(operation.success_response[:schema]).to eq(schema)
  end

  it "normalizes a referenced path-level parameter" do
    expect(operation.path_parameters.first).to include(name: "account_id",
                                                       schema: { type: "string" })
  end

  it "inherits a referenced body parameter from the path" do
    path[:parameters] << path[:post].delete(:parameters).first
    expect(operation.request_schema).to eq(schema)
  end

  it "lets an operation override the inherited body parameter" do
    path[:parameters] << { "$ref": "#/parameters/Payout" }
    path[:post][:parameters] = [{ name: "body", in: "body", schema: { type: "integer" } }]
    expect(operation.request_schema).to eq(type: "integer")
  end

  it "normalizes an inline path parameter too" do
    path[:parameters] = [document[:parameters][:Account]]
    expect(operation.path_parameters.first[:schema]).to eq(type: "string")
  end

  it "normalizes referenced operation-level path parameters" do
    path[:post][:parameters] << path[:parameters].shift
    expect(operation.path_parameters.first[:schema]).to eq(type: "string")
  end

  it "lets operation-level path parameters override inherited parameters" do
    path[:post][:parameters] << { name: "account_id", in: "path", required: true, type: "integer" }
    expect(operation.path_parameters).to contain_exactly(
      a_hash_including(name: "account_id", schema: { type: "integer" })
    )
  end
end
