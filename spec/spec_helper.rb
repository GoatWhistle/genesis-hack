# frozen_string_literal: true

require "rsocket"

# Сетевые вызовы в тестах запрещены: мы проверяем свой код, а не доступность
# чужих серверов. Всё, что должно ходить по HTTP, подменяется здесь же.
require "webmock/rspec"

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Порядок случайный, зерно печатается при падении: так ловятся тесты,
  # которые проходят только благодаря соседям.
  config.order = :random
  Kernel.srand config.seed

  # Файл с упавшими примерами, чтобы `rspec --only-failures` работал.
  config.example_status_persistence_file_path = ".rspec_status"

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
