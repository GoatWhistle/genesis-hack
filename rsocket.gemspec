# frozen_string_literal: true

require_relative "lib/rsocket/version"

Gem::Specification.new do |spec|
  spec.name = "rsocket"
  spec.version = Rsocket::VERSION
  spec.authors = %w[Амир Савелий Иван]

  spec.summary = "Генератор интеграций с платёжными провайдерами"
  spec.description = <<~TEXT
    Читает описание API платёжного провайдера в формате OpenAPI и создаёт
    заготовку интеграции: сервис на Ruby по контракту заказчика, инструкцию
    по подключению, примеры запросов и ответов, тесты.
  TEXT
  spec.homepage = "https://github.com/GoatWhistle/genesis-hack"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "lib/**/*.erb", "lib/**/*.yml", "README.md", "LICENSE"]
  spec.bindir = "bin"
  spec.executables = %w[integrate rsocket]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "rack", "~> 3.1"
  spec.add_dependency "rackup", "~> 2.2"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "webrick", "~> 1.9"
end
