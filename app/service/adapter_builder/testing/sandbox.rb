# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Testing
      # Песочница: исходник и проба исполняются в безымянном модуле, поэтому имена
      # контракта не занимаются и сборки не спорят за константы.
      class Sandbox
        # Исходник не загрузился; это тоже итог проверки.
        class LoadFailure < RuntimeError; end

        PROBE = :Probe

        # @param probe [String] исходник пробы контракта
        # @param source [String] исходник собранного класса
        # @param class_name [String] имя собранного класса, например NovapayService
        def initialize(probe:, source:, class_name:)
          @probe = probe
          @source = source
          @class_name = class_name
        end

        # @return [Object] проба, связанная с собранным классом
        # @raise [LoadFailure] исходник или проба не загрузились
        def call
          space = Module.new
          space.module_eval(@probe, "probe.rb")
          space.module_eval(@source, "#{@class_name.downcase}.rb")
          space.const_get(PROBE).new(@class_name)
        rescue ScriptError, StandardError => e
          raise LoadFailure, "#{e.class}: #{e.message}"
        end
      end
    end
  end
end
