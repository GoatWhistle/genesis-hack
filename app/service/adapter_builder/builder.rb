# frozen_string_literal: true

module Service
  module AdapterBuilder
    # Сценарий целиком: описание API → роли → класс, который сам ходит к провайдеру.
    # Всё внешнее приходит через порты, поэтому сценарий одинаково работает и с
    # файлом на диске, и с подставным источником в тестах.
    class Builder
      # Отчёт лежит рядом с напечатанными файлами: он такой же результат сборки.
      REPORT = "mapping.yml"

      # Итог сборки: разбор, напечатанные файлы и отчёт.
      Result = Struct.new(:blueprint, :files, :report, keyword_init: true) do
        # Главный файл профиля — первый в его списке выходных файлов.
        # @return [String] исходник сгенерированного класса
        def source = files.values.first

        # @return [String] имя файла с этим классом
        def source_name = files.keys.first
      end

      # @param spec_source [Ports::SpecSource] чем читаем описание API
      # @param renderer [Ports::Renderer] чем печатаем класс
      # @param rules [Ports::Rules] правила разбора, обычно Config::Settings
      # @raise [ArgumentError] объект правил не реализует порт
      def initialize(spec_source:, renderer:, rules:)
        @spec_source = spec_source
        @renderer = renderer
        @rules = Ports::Rules.assert!(rules)
      end

      # Собирает сервис целиком.
      # @param reference [String, Pathname] чем адресуется описание API
      # @param provider [String] имя провайдера, например novapay
      # @return [Result] blueprint, напечатанные файлы и отчёт
      # @raise [RuntimeError] не распознаны обязательные роли
      def call(reference:, provider:)
        names = Naming.new(provider, @rules.contract)
        spec = Parsing::SpecParser.new(@spec_source.read(reference)).call
        bindings = classify(spec.operations)
        blueprint = Analysis::BlueprintFactory.new(@rules)
                                              .call(spec: spec, names: names, bindings: bindings)

        report = Rendering::Report.new(blueprint, spec, reference)
        Result.new(blueprint: blueprint, report: report.to_h,
                   files: @renderer.call(blueprint).merge(REPORT => report.to_yaml))
      end

      private

      # Роли раздаёт классификатор, а сценарий следит, чтобы без обязательных
      # ролей сборка не продолжалась молча.
      # @param operations [Array<Models::ApiOperation>]
      # @return [Hash{Symbol => Models::RoleBinding}]
      # @raise [RuntimeError] осталась незанятой обязательная роль
      def classify(operations)
        bindings = Classification::Classifier.new(@rules).call(operations)
        stubs = bindings.values.reject(&:bound?).map(&:role_name)
        missing = stubs.select { |role| @rules.required_role?(role) }
        return bindings if missing.empty?

        raise "не распознаны обязательные роли: #{missing.join(", ")}. " \
              "Правила распознавания — в app/config/rules/base.yml, роли — в профиле контракта"
      end

      # Имена, производные от названия провайдера и профиля контракта: как назвать
      # класс, решает контракт — один собирает сервисы, другой клиентов.
      class Naming
        attr_reader :provider, :contract

        # @param provider [String] имя провайдера в любом виде
        # @param contract [Config::Settings::Contract] профиль, под который собираем
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

        # @return [Hash{Symbol => String}] именами Blueprint — уходит прямо в его конструктор
        def to_h
          { provider: provider, contract: contract.name, class_name: class_name,
            env_prefix: env_prefix }
        end
      end
    end
  end
end
