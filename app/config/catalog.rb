# frozen_string_literal: true

module Config
  # Размещение правил в хранилище; само хранилище скрыто за портом.
  class Catalog
    DEFAULT_CONTRACT = "space_payments"
    BASE = "base.yml"
    CONTRACTS = "contracts"
    CONTRACT = "contract.yml"
    # Имя профиля входит в ключ хранилища, поэтому ограничено набором символов идентификатора.
    NAME = /\A[a-z0-9][a-z0-9_-]*\z/i

    # Имя профиля по умолчанию; переопределяется переменной окружения.
    # @return [String]
    def self.default = ENV.fetch("RSOCKET_CONTRACT", DEFAULT_CONTRACT)

    # @param store [Repositories::Rules::Store] чем читаем и пишем правила
    def initialize(store: Repositories::Rules::Local.new)
      @store = Repositories::Rules::Store.assert!(store)
    end

    # @return [Repositories::Rules::Store]
    attr_reader :store

    # @return [String] общие правила распознавания
    def base = @store.read(BASE)

    # @param name [String] имя профиля
    # @return [String] описание контракта
    # @raise [ArgumentError] профиля с таким именем нет — перечисляем, что есть
    def contract(name)
      key = contract_key(name) if NAME.match?(name.to_s)
      return @store.read(key) if key && @store.exist?(key)

      raise ArgumentError, "контракт не найден: #{name}. Известны: #{names.join(", ")}"
    end

    # @param name [String] имя профиля
    # @param file [String] имя файла шаблона из описания контракта
    # @return [String] шаблон, по которому печатается файл
    def template(name, file) = @store.read(key(name, file))

    # @return [Array<String>] имена доступных профилей по алфавиту
    def names
      @store.list("#{CONTRACTS}/").filter_map { |key| key.split("/")[1] }.uniq.sort
    end

    # @param name [String] имя профиля
    # @return [Array<String>] файлы профиля: описание контракта и шаблоны
    def files(name)
      @store.list("#{CONTRACTS}/#{name}/").map { |key| key.split("/").last }.sort
    end

    # @param name [String] имя профиля
    # @param file [String] имя файла внутри профиля
    # @return [String] ключ в хранилище
    def key(name, file) = "#{CONTRACTS}/#{name}/#{file}"

    # @param name [String]
    # @return [String] ключ описания контракта
    def contract_key(name) = key(name, CONTRACT)
  end
end
