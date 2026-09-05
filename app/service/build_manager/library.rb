# frozen_string_literal: true

module Service
  # Менеджер сборок: небольшой сервис вокруг сценария. Он хранит правила и шаблоны
  # интерфейсов, даёт их читать и править — руками или файлом — и по ним же
  # запускает сборку адаптера.
  module BuildManager
    # Библиотека правил: что лежит в хранилище и как это менять. Хранилище может
    # быть локальным каталогом или бакетом — библиотека одинаково работает с обоими.
    class Library
      # Что за файл лежит по ключу: по расширению видно, правила это или шаблон.
      KINDS = { ".yml" => "rules", ".yaml" => "rules", ".erb" => "template" }.freeze

      # @param catalog [Config::Catalog] раскладка правил поверх хранилища
      def initialize(catalog: Config::Catalog.new)
        @catalog = catalog
      end

      # @return [String] где хранятся правила
      def location = @catalog.store.to_s

      # @param prefix [String] начало ключа: например contracts/space_payments/
      # @return [Array<Hash>] что лежит в хранилище
      def entries(prefix = "")
        @catalog.store.list(prefix).map { |key| { key: key, kind: kind_of(key) } }
      end

      # @param key [String] ключ файла
      # @return [String] содержимое
      # @raise [ArgumentError] такого файла нет
      def read(key) = @catalog.store.read(key)

      # Запись — единственный способ поменять поведение инструмента: и правила, и
      # шаблоны интерфейсов правятся здесь, без пересборки и перезапуска.
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

      # @return [Array<Hash>] профили целиком: чем отличаются и какие роли ищут
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
      # @return [Hash] что роль значит для сборки
      def role(settings, role)
        { name: role.name, title: role.title, threshold: role.threshold,
          required: settings.required_role?(role.name), traits: role.traits }
      end

      # @param key [String]
      # @return [String] вид файла: правила, шаблон или что-то ещё
      def kind_of(key) = KINDS.fetch(::File.extname(key), "other")

      # YAML проверяем на разбор сразу: испорченные правила иначе свалили бы не
      # запись, а следующую сборку — и concerned оказался бы другой человек.
      # @param key [String]
      # @param content [String]
      # @return [void]
      # @raise [ArgumentError] содержимое пустое или YAML не разобрался
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
