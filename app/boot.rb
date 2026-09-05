# frozen_string_literal: true

require "pathname"

module Rsocket
  ROOT = Pathname.new(__dir__).parent.freeze
  APP = ROOT.join("app").freeze
  # Собственное описание сервиса: его отдаёт ручка GET /openapi.yaml.
  OPENAPI = ROOT.join("docs", "openapi.yaml").freeze

  # Порядок важен: адаптеры на этапе загрузки подписываются на порты, а стадии
  # разбора ссылаются друг на друга по ходу конвейера.
  FILES = [
    "models/api_operation", "models/api_spec",
    "models/role_binding", "models/constraint", "models/blueprint",
    "service/adapter_builder/ports",
    "adapter/s3/signature", "adapter/s3/client",
    "repositories/rules/store", "repositories/rules/local", "repositories/rules/s3",
    "adapter/upload/store", "adapter/upload/file", "adapter/upload/s3",
    "config/rule", "config/settings", "config/catalog", "config/vocabulary",
    "config/importer", "config/storage",
    "service/adapter_builder/parsing/schema_probe",
    "service/adapter_builder/parsing/schema_resolver",
    "service/adapter_builder/parsing/spec_parser",
    "service/adapter_builder/classification/classifier",
    "service/adapter_builder/analysis/sample_builder",
    "service/adapter_builder/analysis/status_mapper",
    "service/adapter_builder/analysis/error_mapper",
    "service/adapter_builder/analysis/constraint_factory",
    "service/adapter_builder/analysis/constraint_miner",
    "service/adapter_builder/analysis/payload_builder",
    "service/adapter_builder/analysis/callback_analyzer",
    "service/adapter_builder/analysis/credentials_planner",
    "service/adapter_builder/analysis/call_planner",
    "service/adapter_builder/analysis/fixture_planner",
    "service/adapter_builder/analysis/blueprint_factory",
    "service/adapter_builder/rendering/fixtures",
    "service/adapter_builder/rendering/renderer",
    "service/adapter_builder/rendering/report",
    "service/adapter_builder/builder",
    "adapter/loader/document",
    "adapter/loader/file/spec_loader",
    "adapter/loader/text/spec_reader",
    "service/build_manager/library", "service/build_manager/assembler",
    "controller/cli/summary", "controller/http/api"
  ].freeze

  FILES.each { |file| require APP.join("#{file}.rb").to_s }

  # Собранный сценарий с настоящими адаптерами: чтение описания, печать через ERB
  # и правила из выбранного хранилища. Единственное место, где порты соединяются
  # с реализациями.
  #
  # Профиль контракта решает и правила разбора, и шаблоны печати, поэтому шаблоны
  # берутся у самих правил: подменив профиль, получаем класс под другой интерфейс.
  # @param contract [String] имя профиля контракта
  # @param catalog [Config::Catalog] откуда берутся правила: диск или бакет
  # @param rules [Config::Settings] правила разбора
  # @param spec_source [Ports::SpecSource] откуда берём описание: файл или текст запроса
  # @return [Service::AdapterBuilder::Builder]
  def self.builder(contract: Config::Catalog.default, catalog: Config::Catalog.new,
                   rules: Config::Importer.new(contract, catalog: catalog).call,
                   spec_source: Adapter::Loader::File::SpecLoader.new)
    Service::AdapterBuilder::Builder.new(
      spec_source: spec_source,
      renderer: Service::AdapterBuilder::Rendering::Renderer.new(rules.contract.outputs),
      rules: rules
    )
  end

  # Менеджер сборок на выбранном хранилище: библиотека правил и сборщик адаптеров.
  # @param storage [Config::Storage] где правила и куда уходит результат
  # @param spec_source [Ports::SpecSource] чем читается описание провайдера
  # @return [Hash{Symbol => Object}] library и assembler
  def self.build_manager(storage:, spec_source: Adapter::Loader::File::SpecLoader.new)
    catalog = Config::Catalog.new(store: storage.rules)
    {
      library: Service::BuildManager::Library.new(catalog: catalog),
      assembler: Service::BuildManager::Assembler.new(catalog: catalog, spec_source: spec_source,
                                                      uploader: storage.uploader)
    }
  end

  # HTTP-сервис: описание приходит текстом запроса, результат уходит в хранилище.
  # @param storage [Config::Storage]
  # @return [Controller::Http::Api]
  def self.api(storage: Config::Storage.for(:http))
    Controller::Http::Api.new(
      **build_manager(storage: storage, spec_source: Adapter::Loader::Text::SpecReader.new)
    )
  end
end
