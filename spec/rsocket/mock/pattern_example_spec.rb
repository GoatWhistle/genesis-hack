# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsocket::Mock::PatternExample do
  it "понимает опережающую проверку и не тащит её в значение" do
    value = described_class.new("^(?=ABC)ABC$").call

    expect(value).to eq("ABC")
  end

  it "не выдаёт значение, не подходящее под pattern" do
    generate = -> { described_class.new("^(a)\\1$").call }

    expect(&generate).to raise_error(Rsocket::Mock::ExampleGenerationError, /pattern/)
  end

  it "внятно сообщает о сломанном регулярном выражении" do
    generate = -> { described_class.new("[").call }

    expect(&generate).to raise_error(Rsocket::Mock::ExampleGenerationError, /Некорректный pattern/)
  end
end
