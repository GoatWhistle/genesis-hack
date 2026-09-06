# frozen_string_literal: true

module Service
  module AdapterBuilder
    # Интерфейсы на стороне потребителя: сценарий описывает, адаптеры реализуют.
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

      # Раздача ролей по операциям: какая операция закрывает какую роль контракта.
      module Classifier
        # @param _operations [Array<Models::ApiOperation>] все операции описания
        # @return [Hash{Symbol => Models::RoleBinding}] роль → привязка, включая заглушки
        # @raise [NotImplementedError] адаптер не реализовал порт
        def call(_operations)
          raise NotImplementedError, "#{self.class}#call"
        end

        # @param candidate [Object] проверяемая реализация порта
        # @return [Object] тот же объект, если он реализует порт
        # @raise [ArgumentError] объект не отвечает на call
        def self.assert!(candidate)
          return candidate if candidate.respond_to?(:call)

          raise ArgumentError, "классификатор не отвечает на: call"
        end
      end

      # Проверка собранного класса на его фикстурах. Реализация — Testing::Tester.
      module Tester
        # @param _source [String] исходник напечатанного класса
        # @param _blueprint [Models::Blueprint] всё, что инструмент решил
        # @return [Testing::Report] что проверено и что не сошлось
        # @raise [NotImplementedError] адаптер не реализовал порт
        def call(_source:, _blueprint:)
          raise NotImplementedError, "#{self.class}#call"
        end

        # @param candidate [Object] проверяемая реализация порта
        # @return [Object] тот же объект, если он реализует порт
        # @raise [ArgumentError] объект не отвечает на call
        def self.assert!(candidate)
          return candidate if candidate.respond_to?(:call)

          raise ArgumentError, "проверяльщик не отвечает на: call"
        end
      end

      # Правила разбора и профиль контракта. Реализация — Config::Settings.
      module Rules
        REQUIRED_METHODS = %i[
          contract ordered_roles roles_with role_with required_role? status_sources
          contract_status error_for known_error_codes field_for entry_for
          header_kind header_source condition auth_template
          payload_fields requisite_fields callback_fields headers constraints path_params http
        ].freeze

        # Проверка, что объект реализует порт правил.
        # @param candidate [Object] проверяемая реализация порта
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
