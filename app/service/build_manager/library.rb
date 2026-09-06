# frozen_string_literal: true

module Service
  # Менеджер сборок: правила, шаблоны и запуск сборки по ним.
  module BuildManager
    # Библиотека правил: что лежит в хранилище и как это менять.
    class Library
      # Вид файла определяется по расширению ключа.
      KINDS = { ".yml" => "rules", ".yaml" => "rules", ".erb" => "template",
                ".rb" => "probe" }.freeze

      # @param catalog [Config::Catalog] размещение правил в хранилище
      def initialize(catalog: Config::Catalog.new)
        @catalog = catalog
      end

      # @return [String] адрес хранилища правил
      def location = @catalog.store.to_s

      # @param prefix [String] начало ключа: например contracts/space_payments/
      # @return [Array<Hash>] файлы хранилища
      def entries(prefix = "")
        @catalog.store.list(prefix).map { |key| { key: key, kind: kind_of(key) } }
      end

      # @param key [String] ключ файла
      # @return [String] содержимое
      # @raise [ArgumentError] такого файла нет
      def read(key) = @catalog.store.read(key)

      # Правка правил и шаблонов идёт без пересборки и перезапуска.
      # @param key [String] ключ файла
      # @param content [String] новое содержимое
      # @return [Hash] что записали
      # @raise [ArgumentError] пустое содержимое или испорченный YAML
      def save(key, content)
        check!(key, content)
        @catalog.store.write(key, content)
        { key: key, kind: kind_of(key), bytes: content.bytesize }
      end

      # @return [Array<String>] имена профилей контрактов
      def names = @catalog.names

      # @return [Array<Hash>] профили целиком: состав и искомые роли
      def profiles = names.map { |name| profile(name) }

      # @param name [String] имя профиля
      # @return [Hash] описание профиля
      def profile(name)
        settings = Config::Importer.new(name, catalog: @catalog).call
        { name: name, title: settings.contract.title,
          default: name == Config::Catalog.default, files: @catalog.files(name),
          outputs: settings.contract.outputs.map { |output| output.name_for("<provider>") },
          roles: settings.ordered_roles.map { |role| role(settings, role) } }
      end

      private

      # @param settings [Config::Settings]
      # @param role [Config::Settings::Role]
      # @return [Hash] описание роли для сборки
      def role(settings, role)
        { name: role.name, title: role.title, threshold: role.threshold,
          required: settings.required_role?(role.name), traits: role.traits }
      end

      # @param key [String]
      # @return [String] вид файла: правила, шаблон, проба или прочее
      def kind_of(key) = KINDS.fetch(::File.extname(key), "other")

      # YAML разбирается при записи: иначе ошибка всплывёт на следующей сборке.
      # @param key [String]
      # @param content [String]
      # @return [void]
      # @raise [ArgumentError] пустое содержимое или ошибка разбора YAML
      def check!(key, content)
        raise ArgumentError, "пустое содержимое для #{key}" if content.to_s.strip.empty?
        return unless kind_of(key) == "rules"

        YAML.safe_load(content, aliases: true)
      rescue Psych::Exception => e
        raise ArgumentError, "не разобрать YAML для #{key}: #{e.message}"
      end
    end
  end
end
