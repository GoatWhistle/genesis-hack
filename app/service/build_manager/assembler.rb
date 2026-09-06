# frozen_string_literal: true

module Service
  module BuildManager
    # Запуск сборки: описание на входе, файлы в хранилище результата на выходе.
    class Assembler
      Outcome = Struct.new(:provider, :contract, :files, :report, :warnings, :locations,
                           :checks, keyword_init: true)

      # @param catalog [Config::Catalog] источник правил и шаблонов
      # @param uploader [Adapter::Upload::Store] хранилище результата
      # @param spec_source [Ports::SpecSource] источник описания провайдера
      def initialize(catalog: Config::Catalog.new, uploader: Adapter::Upload::File.new,
                     spec_source: Adapter::Loader::File::SpecLoader.new)
        @catalog = catalog
        @uploader = Adapter::Upload::Store.assert!(uploader)
        @spec_source = spec_source
      end

      # @return [String] адрес хранилища результата
      def destination = @uploader.to_s

      # @param spec [String, Pathname] адрес описания: путь или его текст
      # @param provider [String] имя провайдера
      # @param contract [String] имя профиля контракта
      # @param classifier [String, Symbol, #call, nil] способ раздачи ролей; nil — по умолчанию
      # @param tester [Boolean, #call, nil] проверять ли собранный класс на его фикстурах;
      #   проверка исполняет напечатанный код и включается явно
      # @return [Outcome] результат сборки, размещение файлов и итог проверки
      def call(spec:, provider:, contract: Config::Catalog.default, classifier: nil, tester: nil)
        result = builder(contract, classifier, tester).call(reference: spec, provider: provider)
        blueprint = result.blueprint

        Outcome.new(provider: blueprint.provider, contract: blueprint.contract,
                    files: result.files, report: result.report, warnings: blueprint.warnings,
                    checks: result.checks,
                    locations: @uploader.store(blueprint.provider, result.files))
      end

      private

      # @param contract [String]
      # @param classifier [String, Symbol, #call]
      # @param tester [Boolean, #call, nil]
      # @return [Service::AdapterBuilder::Builder]
      def builder(contract, classifier, tester)
        Rsocket.builder(contract: contract, catalog: @catalog, spec_source: @spec_source,
                        classifier: classifier, tester: tester)
      end
    end
  end
end
