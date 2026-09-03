# frozen_string_literal: true

require "spec_helper"
require "rack/mock"

RSpec.describe Rsocket::Mock::Server do
  subject(:server) { described_class.new(ir_spec) }

  let(:ir_spec) { normalize_example("novapay") }

  def normalize_example(name)
    path = File.join(Rsocket.root, "examples", name, "provider_api.yaml")
    Rsocket::Spec::Normalizer.normalize(Rsocket::Spec::Loader.load(path))
  end

  def request(operation)
    path = operation.path.gsub(/\{[^}]+\}/, "sample-id")
    Rack::MockRequest.new(server).request(operation.http_method.to_s.upcase, path)
  end

  %w[novapay swiftpay kassabox].each do |name|
    context "with the #{name} description" do
      let(:ir_spec) { normalize_example(name) }

      it "serves every described operation" do
        responses = ir_spec.operations.map { |operation| request(operation) }

        expect(responses.map(&:status)).to all(be_between(200, 299))
      end
    end
  end

  it "returns the first documented example" do
    operation = ir_spec.operations.find { |item| item.operation_id == "createPayout" }
    response = request(operation)

    expect(JSON.parse(response.body)).to include("id" => "np_7f3a9b2c", "status" => "pending")
  end

  it "returns JSON for an unknown route", :aggregate_failures do
    response = Rack::MockRequest.new(server).get("/not-described")

    expect(response.status).to eq(404)
    expect(JSON.parse(response.body)).to include("error" => include("code" => "route_not_found"))
  end

  it "distinguishes an unknown method from an unknown route" do
    response = Rack::MockRequest.new(server).put("/payouts")

    expect(response.status).to eq(405)
  end

  it "starts the Rack app with WEBrick" do
    allow(Rackup::Server).to receive(:start)

    server.start(port: 4123, host: "127.0.0.2")

    expect(Rackup::Server).to have_received(:start).with(
      hash_including(app: server, server: "webrick", Port: 4123, Host: "127.0.0.2")
    )
  end

  describe "schema-generated responses" do
    let(:ir_spec) do
      response = Rsocket::Ir::Response.new(code: 200, fields: generated_fields)
      operation = Rsocket::Ir::Operation.new(
        http_method: :get, path: "/generated/{id}", responses: { 200 => response }
      )
      Rsocket::Ir::Spec.new(operations: [operation])
    end

    let(:generated_fields) do
      [
        field("reference", type: "string", pattern: "^TX-\\d{4}$"),
        field("state", type: "string", enum: %w[ready done]),
        field("amount", type: "integer", minimum: 7),
        field("short", type: "string", max_length: 3),
        field("items", type: "array", item: field("item", type: "boolean"))
      ]
    end

    let(:generated_body) do
      JSON.parse(Rack::MockRequest.new(server).get("/generated/42").body)
    end

    def field(name, **attributes)
      Rsocket::Ir::Field.new(name:, **attributes)
    end

    it "respects schema constraints", :aggregate_failures do
      expect(generated_body.fetch("reference")).to match(/\ATX-\d{4}\z/)
      expect(generated_body.fetch("state")).to eq("ready")
      expect(generated_body.fetch("amount")).to eq(7)
      expect(generated_body.fetch("short").length).to be <= 3
      expect(generated_body.fetch("items")).to eq([false])
    end

    context "when a pattern cannot be generated safely" do
      let(:generated_fields) do
        [field("reference", type: "string", pattern: "^(a)\\1$")]
      end

      it "returns a readable JSON error instead of an invalid example" do
        response = Rack::MockRequest.new(server).get("/generated/42")
        error = JSON.parse(response.body).fetch("error")

        expect([response.status, error.fetch("code"), error.fetch("message")]).to match(
          [500, "example_generation_failed", /pattern/]
        )
      end
    end
  end

  describe "response headers" do
    let(:ir_spec) do
      header = Rsocket::Ir::Field.new(name: "Retry-After", type: "integer", minimum: 10)
      response = Rsocket::Ir::Response.new(code: 429, headers: [header])
      operation = Rsocket::Ir::Operation.new(
        http_method: :get, path: "/limited", responses: { 429 => response }
      )
      Rsocket::Ir::Spec.new(operations: [operation])
    end

    it "generates documented headers" do
      response = Rack::MockRequest.new(server).get("/limited")

      expect(response["retry-after"]).to eq("10")
    end
  end

  describe "webhook delivery" do
    let(:url) { "https://merchant.example/hooks/transfer" }
    let(:secret) { "test-secret" }
    let(:payload) { { "event" => "transfer.paid", "transfer_id" => "trf_42" } }
    let(:invalid_delivery) do
      lambda do
        server.deliver_webhook(
          url:, payload:, secret:, signature_header:, invalid_signature: true
        )
      end
    end

    def signature_header
      "X-NovaPay-Signature"
    end

    before do
      stub_request(:post, url).to_return do |request|
        expected = OpenSSL::HMAC.hexdigest("SHA256", secret, request.body)
        actual = request.headers.find { |key, _value| key.casecmp?(signature_header) }&.last
        status = actual == expected ? 204 : 401
        { status: status, body: "" }
      end
    end

    it "sends a signature accepted by the receiver" do
      response = server.deliver_webhook(url:, payload:, secret:, signature_header:)

      expect(response.status).to eq(204)
    end

    it "raises a delivery error when a corrupted signature is rejected", :aggregate_failures do
      expect(&invalid_delivery).to raise_error(Rsocket::Mock::DeliveryError, /HTTP 401/)
      expect(a_request(:post, url)).to have_been_made.once
    end
  end
end
