# frozen_string_literal: true

module Service
  module AdapterBuilder
    # Интерфейсы объявлены там, где используются: сценарий сборки описывает, что
    # ему нужно от внешнего мира, а адаптеры под это подписываются. Ни файловой
    # системы, ни ERB сценарий не знает — в тестах и то, и другое подменяется.
    module Ports
      # Откуда берём описание API.
      module SpecSource
        # @param _reference [String, Pathname] чем адресуется описание: путь, URL, ключ
        # @return [Hash] сырое описание, ключи символами
        # @raise [NotImplementedError] адаптер не реализовал порт
        def read(_reference)
          raise NotImplementedError, "#{self.class}#read"
        end
      end

      # Чем печатаем выходные файлы.
      module Renderer
        # @param _blueprint [Models::Blueprint] всё, что нужно напечатать
        # @return [Hash{String => String}] имя файла → его содержимое
        # @raise [NotImplementedError] адаптер не реализовал порт
        def call(_blueprint)
          raise NotImplementedError, "#{self.class}#call"
        end
      end

      # Кто раздаёт роли операциям описания. Реализаций три: правила с весами
      # (Classification::Classifier), косинусовая близость эмбеддингов и запрос в
      # LLM. Сценарий сборки одинаково работает с любой.
      module Classifier
        # @param _operations [Array<Models::ApiOperation>] все операции описания
        # @return [Hash{Symbol => Models::RoleBinding}] роль → привязка, включая заглушки
        # @raise [NotImplementedError] адаптер не реализовал порт
        def call(_operations)
          raise NotImplementedError, "#{self.class}#call"
        end

        # @param candidate [Object] предполагаемый классификатор
        # @return [Object] тот же объект, если он подходит
        # @raise [ArgumentError] объект не умеет раздавать роли
        def self.assert!(candidate)
          return candidate if candidate.respond_to?(:call)

          raise ArgumentError, "классификатор не отвечает на: call"
        end
      end

      # Чем текст превращается в вектор. Нужен смысловому классификатору: сравнивать
      # описание операции с эталоном роли он умеет только числами.
      module Embedder
        # @param _texts [Array<String>] тексты одной пачкой — так дешевле и быстрее
        # @return [Array<Array<Float>>] векторы в том же порядке, что и тексты
        # @raise [NotImplementedError] адаптер не реализовал порт
        def embed(_texts)
          raise NotImplementedError, "#{self.class}#embed"
        end
      end

      # Правила разбора вместе с профилем контракта, под который собирается класс.
      # Реализация — Config::Settings.
      module Rules
        REQUIRED_METHODS = %i[
          contract ordered_roles roles_with role_with required_role? status_sources
          contract_status error_for known_error_codes field_for entry_for
          header_kind header_source condition auth_template
          payload_fields requisite_fields callback_fields headers constraints path_params http
        ].freeze

        # Проверка, что переданный объект действительно отвечает за правила.
        # @param candidate [Object] предполагаемая реализация порта
        # @return [Object] тот же объект, если он подходит
        # @raise [ArgumentError] объект не отвечает на часть REQUIRED_METHODS
        def self.assert!(candidate)
          missing = REQUIRED_METHODS.reject { |name| candidate.respond_to?(name) }
          return candidate if missing.empty?

          raise ArgumentError, "объект правил не отвечает на: #{missing.join(", ")}"
        end
      end
    end
  end
end
