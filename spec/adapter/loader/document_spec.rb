# frozen_string_literal: true

RSpec.describe Adapter::Loader::Document do
  describe ".parse_yaml" do
    it "разбирает дату без кавычек, а не падает на ней" do
      document = described_class.parse_yaml("release_date: 2024-01-01")
      expect(document[:release_date]).to eq(Date.new(2024, 1, 1))
    end

    it "разбирает дату-время без кавычек" do
      document = described_class.parse_yaml("updated_at: 2024-01-01T12:00:00Z")
      expect(document[:updated_at]).to be_a(Time)
    end

    it "по-прежнему не разбирает неизвестные теги" do
      expect { described_class.parse_yaml("value: !ruby/object {}") }
        .to raise_error(ArgumentError, /не разобрать YAML/)
    end
  end
end
