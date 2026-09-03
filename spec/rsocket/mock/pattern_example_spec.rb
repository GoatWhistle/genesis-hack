# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Mock::PatternExample do
  it "supports zero-width lookahead without putting it into the value" do
    value = described_class.new("^(?=ABC)ABC$").call

    expect(value).to eq("ABC")
  end

  it "never returns a value that violates the pattern" do
    generate = -> { described_class.new("^(a)\\1$").call }

    expect(&generate).to raise_error(Rsocket::Mock::ExampleGenerationError, /pattern/)
  end

  it "reports malformed regular expressions clearly" do
    generate = -> { described_class.new("[").call }

    expect(&generate).to raise_error(Rsocket::Mock::ExampleGenerationError, /Некорректный pattern/)
  end
end
