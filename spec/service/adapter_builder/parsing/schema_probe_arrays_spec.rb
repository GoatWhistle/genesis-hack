# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Parsing::SchemaProbe do
  let(:item) do
    { type: "object", properties: { status: { type: "string", enum: %w[pending completed] } } }
  end
  let(:schema) { { type: "array", items: item } }

  it "сохраняет индекс массива в пути к статусу" do
    expect(described_class.new(schema).find([/status/]).path).to eq([0, "status"])
  end

  it "разрешает ссылки на схемы элементов массива" do
    document = { components: { schemas: { Item: item } } }
    resolver = Service::AdapterBuilder::Parsing::SchemaResolver.new(document)
    resolved = resolver.call(type: "array", items: { "$ref": "#/components/schemas/Item" })
    expect(described_class.new(resolved).find([/status/]).values).to eq(%w[pending completed])
  end
end
