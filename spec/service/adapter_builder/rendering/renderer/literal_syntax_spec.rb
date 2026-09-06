# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Rendering::Renderer::Literal do
  let(:renderer) { Object.new.extend(described_class) }
  let(:unknowns) do
    { type: "object", required: %w[unmapped_alpha unmapped_beta],
      properties: { unmapped_alpha: { type: "string" }, unmapped_beta: { type: "string" } } }
  end
  let(:payload) do
    operation = Models::ApiOperation.new(operation_id: "createPayout", http_method: :post,
                                         path: "/payouts", request: { schema: schema })
    Service::AdapterBuilder::Analysis::PayloadBuilder.new(rules).call(operation: operation)
  end
  let(:source) { "{\n#{renderer.payload_literal(payload.fields, 2)}\n}" }

  %w[flat nested].each do |shape|
    context "когда #{shape} payload содержит последовательные неизвестные обязательные поля" do
      let(:schema) do
        properties = shape == "flat" ? unknowns[:properties] : { details: unknowns }
        { type: "object", required: properties.keys.map(&:to_s),
          properties: properties.merge(currency: { type: "string" }) }
      end

      it "compiles the payload including the following known field" do
        expect { RubyVM::InstructionSequence.compile(source) }.not_to raise_error
      end

      it "keeps unknown fields as explicit TODO placeholders" do
        expect(source).to include("unmapped_alpha: nil", "unmapped_beta: nil", "currency:")
      end

      it "emits a TODO for each unknown required field" do
        expect(source.scan("# TODO: правила не знают, чем заполнить это поле").size).to eq(2)
      end

      it "preserves warnings that the required fields remain unfilled" do
        prefix = shape == "flat" ? "" : "details."
        expect(payload.warnings).to match_array(%w[unmapped_alpha unmapped_beta].map do |name|
          "поле #{prefix}#{name} обязательно, но правила не знают, чем его заполнить"
        end)
      end
    end
  end
end
