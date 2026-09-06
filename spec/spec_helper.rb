# frozen_string_literal: true

require "tmpdir"
require_relative "../app/boot"
require_relative "support/contract"

# Подставные сервисы нужны только смысловым классификаторам; их может не быть.
stubs = File.expand_path("support/classification.rb", __dir__)
require stubs if File.exist?(stubs)

RSpec.configure do |config|
  config.expect_with(:rspec) do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Проверка ходит к своему серверу на localhost, поэтому WebMock его пропускает.
  config.before do
    WebMock.disable_net_connect!(allow_localhost: true) if defined?(WebMock)
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

EXAMPLES = Dir[File.expand_path("../examples/*/provider_api.yaml", __dir__)].freeze

def example_spec(provider)
  File.expand_path("../examples/#{provider}/provider_api.yaml", __dir__)
end

DEFAULT_CONTRACT = "space_payments"

def rules(contract = DEFAULT_CONTRACT)
  @rules ||= {}
  @rules[contract] ||= Config::Importer.call(contract)
end

# Сборка на настоящих адаптерах: внешнее — только чтение файла.
def build_service(provider, contract: DEFAULT_CONTRACT)
  Rsocket.builder(rules: rules(contract))
         .call(reference: example_spec(provider), provider: provider)
end

# Грузит в процесс тот самый файл, который уедет заказчику.
def load_service(provider, contract: DEFAULT_CONTRACT)
  result = build_service(provider, contract: contract)
  file = Pathname.new(Dir.mktmpdir).join(result.source_name)
  file.write(result.source)
  require file.to_s
end

def operations_for(provider)
  document = Adapter::Loader::File::SpecLoader.new.read(example_spec(provider))
  Service::AdapterBuilder::Parsing::SpecParser.new(document).call.operations
end
