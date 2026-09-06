# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Classification::Classifier do
  let(:create) { { operationId: "createPayout", summary: "Create a payout" } }
  let(:event) { { summary: "Payout webhook notification" } }
  let(:document) { { openapi: "3.1.0", paths: { "/payouts" => { post: create } } } }

  def binding
    operations = Service::AdapterBuilder::Parsing::SpecParser.new(document).call.operations
    described_class.new(rules).call(operations).fetch(:process_callback)
  end

  def nested_callback(name, body)
    { name => { "{$request.body#/callbackUrl}" => { post: body } } }
  end

  def other_creation(callbacks)
    document[:paths]["/payment-links"] = { post: {
      operationId: "createPaymentLink", callbacks: callbacks
    } }
  end

  def payload_event(properties)
    document[:webhooks] = { onStatus: { post: {
      summary: "Status webhook notification",
      requestBody: { content: { "application/json": {
        schema: { type: "object", properties: properties }
      } } }
    } } }
  end

  def subscription(events)
    body = { summary: "Webhook event notification",
             requestBody: { content: { "application/json": {
               schema: { type: "object", properties: { type: { type: "string", enum: events } } }
             } } } }
    { operationId: "createWebhook", tags: ["Webhooks"],
      callbacks: nested_callback(:WebhookRequest, body) }
  end

  def register_webhook(events)
    document[:paths]["/webhooks"] = { post: subscription(events) }
  end

  def post_operation(path, operation_id, summary)
    document[:paths][path] = { post: { operationId: operation_id, summary: summary } }
  end

  it "links a signal to an enqueued disbursement" do
    document[:paths] = {}
    post_operation("/disbursements", "enqueueDisbursement", "Queue a disbursement for execution")
    post_operation("/hooks/disbursement", "disbursementSignal", "Disbursement signal notification")
    expect(binding.operation&.method_name).to eq("disbursement_signal")
  end

  it "links a registered webhook with an explicit event for the chosen resource" do
    document[:paths] = {}
    post_operation("/external_card_transfers", "createExternalCardTransfer",
                   "Create an external card transfer")
    register_webhook(%w[CARD.CREATED EXTERNAL_CARD_TRANSFER.UPDATED])
    expect(binding.operation&.method_name).to eq("webhook_request")
  end

  it "does not infer wire events from generic transaction or other transfer events" do
    document[:paths] = {}
    post_operation("/wires", "createWire", "Send a wire transfer")
    register_webhook(%w[TRANSACTION.POSTED.UPDATED EXTERNAL_CARD_TRANSFER.UPDATED])
    expect(binding).not_to be_bound
  end

  it "rejects registered foreign flows even when their enums contain payment or payout" do
    register_webhook(%w[PAYMENT_LINK.UPDATED CARD_AUTHORIZATION.CREATED PAYOUT_INCOMING.CREATED])
    expect(binding).not_to be_bound
  end

  it "requires explicit event types for registered webhooks" do
    document[:paths]["/webhooks"] = { post: subscription([]) }
    expect(binding).not_to be_bound
  end

  it "does not use event enums to bypass a foreign payment-link parent" do
    document[:paths]["/payment-links"] = { post: subscription(%w[PAYOUT.UPDATED]).merge(
      operationId: "createPaymentLink"
    ) }
    expect(binding).not_to be_bound
  end

  it "refuses equally justified registered callbacks" do
    document[:paths]["/webhooks"] = { post: subscription(%w[PAYOUT.UPDATED]) }
    document[:paths]["/callbacks"] = { post: subscription(%w[PAYOUT.CREATED]) }
    expect(binding).to have_attributes(bound?: false, explanation: a_string_including("неоднознач"))
  end

  it "chooses payout webhooks over competing payment links" do
    document[:webhooks] = { webhook_payment_links: { post: { summary: "Payment link webhook" } },
                            webhook_payouts: { post: event } }
    expect(binding.operation&.method_name).to eq("webhook_payouts")
  end

  it "preserves callbacks declared in paths" do
    document[:paths]["/webhooks/payout"] = { post: event.merge(operationId: "payoutWebhook") }
    expect(binding.operation&.method_name).to eq("payout_webhook")
  end

  it "rejects competing equally justified payout events with an explanation" do
    document[:webhooks] = { payout_settled: { post: event }, payout_failed: { post: event } }
    expect(binding).to have_attributes(bound?: false, explanation: a_string_including("неоднознач"))
  end

  it "rejects incoming payment and card authorization notifications" do
    document[:webhooks] = {
      payment_received: { post: { summary: "Payment webhook notification" } },
      card_authorization: { post: { summary: "Card authorization webhook" } }
    }
    expect(binding).not_to be_bound
  end

  it "requires a recognized creation operation" do
    document[:paths] = {}
    document[:webhooks] = { payout_settled: { post: event } }
    expect(binding).not_to be_bound
  end

  it "uses the actual parent for generic nested callbacks with competing events" do
    create[:callbacks] = nested_callback(:onStatus, summary: "Status webhook notification")
    other_creation(create[:callbacks])
    expect(binding.operation).to have_attributes(
      method_name: "on_status", callback_origin: have_attributes(operation_id: "createPayout")
    )
  end

  it "uses resource-specific payload fields for a generically named webhook" do
    payload_event(payout_id: { type: "string" })
    expect(binding.operation&.method_name).to eq("on_status")
  end

  it "does not infer a flow from generic payload fields" do
    payload_event(id: {}, status: {}, amount: {})
    expect(binding).not_to be_bound
  end

  it "does not use a payout-named callback owned by another operation" do
    other_creation(nested_callback(:payoutStatus, event))
    expect(binding).not_to be_bound
  end

  it "prefers a callback owned by creation over an unrelated named webhook" do
    create[:callbacks] = nested_callback(:onStatus, summary: "Status webhook notification")
    document[:webhooks] = { payout_settled: { post: event } }
    expect(binding.operation&.method_name).to eq("on_status")
  end

  it "rejects payment received even when the chosen outgoing resource is payments" do
    document[:paths] = { "/payments" => { post: {
      operationId: "createPayment", summary: "Create a transfer to another account"
    } } }
    document[:webhooks] = { payment_received: { post: { summary: "Payment webhook" } } }
    expect(binding).not_to be_bound
  end
end
