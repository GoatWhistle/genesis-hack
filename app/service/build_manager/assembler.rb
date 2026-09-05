# frozen_string_literal: true

module Service
  module BuildManager
    # Запуск сборки адаптера: описание провайдера на входе, напечатанные файлы в
    # хранилище результата на выходе. Здесь же соединяются три сменные части —
    # откуда правила, откуда описание и куда складывать результат.
    class Assembler
      Outcome = Struct.new(:provider, :contract, :files, :report, :warnings, :locations,
                           keyword_init: true)

      # @param catalog [Config::Catalog] откуда берутся правила и шаблоны
      # @param uploader [Adapter::Upload::Store] куда складывается результат
      # @param spec_source [Ports::SpecSource] чем читается описание провайдера
      def initialize(catalog: Config::Catalog.new, uploader: Adapter::Upload::File.new,
                     spec_source: Adapter::Loader::File::SpecLoader.new)
        @catalog = catalog
        @uploader = Adapter::Upload::Store.assert!(uploader)
        @spec_source = spec_source
      end

      # @return [String] куда уходит результат
      def destination = @uploader.to_s

      # @param spec [String, Pathname] чем адресуется описание: путь или сам текст
      # @param provider [String] имя провайдера
      # @param contract [String] имя профиля контракта
      # @return [Outcome] что собралось и куда легло
      def call(spec:, provider:, contract: Config::Catalog.default)
        result = builder(contract).call(reference: spec, provider: provider)
        blueprint = result.blueprint

        Outcome.new(provider: blueprint.provider, contract: blueprint.contract,
                    files: result.files, report: result.report, warnings: blueprint.warnings,
                    locations: @uploader.store(blueprint.provider, result.files))
      end

      private

      # @param contract [String]
      # @return [Service::AdapterBuilder::Builder]
      def builder(contract)
        Rsocket.builder(contract: contract, catalog: @catalog, spec_source: @spec_source)
      end
    end
  end
end
