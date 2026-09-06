# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Analysis::FixturePlanner do
  let(:operation) do
    schema = { type: "object", properties: { payout: { type: "object", properties: {
      status: { type: "string", enum: %w[pending completed] }
    } } } }
    Models::ApiOperation.new(operation_id: "payoutWebhook", http_method: :post, path: "/webhook",
                             request: { schema: schema })
  end
  let(:bindings) do
    { process_callback: Models::RoleBinding.new(role: rules.role(:process_callback), operation: operation) }
  end
  let(:statuses) do
    Service::AdapterBuilder::Analysis::StatusMapper::Result.new(
      status_map: { "pending" => "in_progress", "completed" => "approved" }, event_map: {}
    )
  end
  let(:callback) do
    Service::AdapterBuilder::Analysis::CallbackAnalyzer.new(rules).call(operation)
  end

  it "не изменяет вложенное тело предыдущего сценария callback" do
    result = described_class.new(rules).call(bindings: bindings, statuses: statuses,
                                             callback: callback)
    expect(result.callbacks.map { |item| item.payload.dig("payout", "status") })
      .to eq(%w[pending completed])
  end
end
