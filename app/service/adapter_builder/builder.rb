# frozen_string_literal: true

module Service
  module AdapterBuilder
    # Сценарий сборки: описание API → роли → класс, обращающийся к провайдеру.
    class Builder
      # Отчёт входит в результат сборки наравне с напечатанными файлами.
      REPORT = "mapping.yml"

      # Результат сборки; checks равен nil, если проверка не выполнялась.
      Result = Struct.new(:blueprint, :files, :report, :checks, keyword_init: true) do
        # Основной файл профиля — первый в списке выходных файлов.
        # @return [String] исходник сгенерированного класса
        def source = files.values.first

        # @return [String] имя файла с этим классом
        def source_name = files.keys.first
      end

      # @param spec_source [Ports::SpecSource] источник описания API
      # @param renderer [Ports::Renderer] печать выходных файлов
      # @param rules [Ports::Rules] правила разбора, обычно Config::Settings
      # @param classifier [Ports::Classifier, nil] распределение ролей; по умолчанию —
      #   правила с весами из конфигурации, единственная реализация без внешних вызовов
      # @param tester [Ports::Tester, nil] проверка собранного класса; nil — сборка
      #   завершается печатью файлов
      # @raise [ArgumentError] объект правил, классификатора или проверки не реализует порт
      def initialize(spec_source:, renderer:, rules:, classifier: nil, tester: nil)
        @spec_source = spec_source
        @renderer = renderer
        @rules = Ports::Rules.assert!(rules)
        @classifier = Ports::Classifier.assert!(classifier || Classification::Classifier.new(rules))
        @tester = tester && Ports::Tester.assert!(tester)
      end

      # Выполняет сборку целиком.
      # @param reference [String, Pathname] адрес описания API
      # @param provider [String] имя провайдера, например novapay
      # @return [Result] blueprint, напечатанные файлы, отчёт и проверка
      # @raise [RuntimeError] не распознаны обязательные роли
      def call(reference:, provider:)
        spec = Parsing::SpecParser.new(@spec_source.read(reference)).call
        blueprint = Analysis::BlueprintFactory.new(@rules).call(
          spec: spec, names: Naming.new(provider, @rules.contract),
          bindings: classify(spec.operations)
        )
        result(blueprint, spec, reference)
      end

      private

      # Печать, проверка напечатанного и запись итога в отчёт.
      # @param blueprint [Models::Blueprint]
      # @param spec [Models::ApiSpec] разобранное описание
      # @param reference [String, Pathname] откуда описание взято
      # @return [Result]
      def result(blueprint, spec, reference)
        files = @renderer.call(blueprint)
        checks = verify(files, blueprint)
        report = Rendering::Report.new(blueprint, spec, reference, checks: checks)
        Result.new(blueprint: blueprint, report: report.to_h, checks: checks,
                   files: files.merge(REPORT => report.to_yaml))
      end

      # Последняя ступень: класс вызывается на своих фикстурах, итог идёт в отчёт.
      # @param files [Hash{String => String}] напечатанные файлы
      # @param blueprint [Models::Blueprint]
      # @return [Testing::Report, nil] nil, если проверять некому
      def verify(files, blueprint)
        @tester&.call(source: files.values.first, blueprint: blueprint)
      end

      # Без обязательной роли сборка прерывается.
      # @param operations [Array<Models::ApiOperation>]
      # @return [Hash{Symbol => Models::RoleBinding}]
      # @raise [RuntimeError] осталась незанятой обязательная роль
      def classify(operations)
        bindings = @classifier.call(operations)
        stubs = bindings.values.reject(&:bound?).map(&:role_name)
        missing = stubs.select { |role| @rules.required_role?(role) }
        return bindings if missing.empty?

        raise "не распознаны обязательные роли: #{missing.join(", ")}. " \
              "Правила распознавания — в app/config/rules/base.yml, роли — в профиле контракта"
      end

      # Имена от названия провайдера и профиля; имя класса задаёт контракт.
      class Naming
        attr_reader :provider, :contract

        # @param provider [String] имя провайдера в произвольном написании
        # @param contract [Config::Settings::Contract] профиль сборки
        # @raise [ArgumentError] после нормализации имя оказалось пустым
        def initialize(provider, contract)
          @provider = provider.to_s.downcase.gsub(/[^a-z0-9]+/, "_")
          @contract = contract
          raise ArgumentError, "имя провайдера пустое" if @provider.empty?
        end

        # @return [String] Novapay
        def camel = provider.split("_").map(&:capitalize).join
        # @return [String] имя генерируемого класса: NovapayService или NovapayClient
        def class_name = "#{camel}#{contract.class_suffix}"
        # @return [String] префикс переменных окружения: NOVAPAY
        def env_prefix = provider.upcase

        # @return [Hash{Symbol => String}] поля Blueprint для его конструктора
        def to_h
          { provider: provider, contract: contract.name, class_name: class_name,
            env_prefix: env_prefix }
        end
      end
    end
  end
end
