# frozen_string_literal: true

module Config
  # Где лежат правила и куда уходит результат. Выбор делается один раз при запуске
  # и дальше не меняется: командная строка работает локально, HTTP-сервер — в S3.
  #
  # S3 можно не настраивать вовсе: тогда обе стороны работают с диском, и для
  # запуска инструмента не нужно ничего, кроме самого репозитория.
  class Storage
    LOCAL = "local"
    S3 = "s3"
    KINDS = [LOCAL, S3].freeze
    REQUIRED = %w[RSOCKET_S3_ENDPOINT RSOCKET_S3_BUCKET
                  RSOCKET_S3_ACCESS_KEY_ID RSOCKET_S3_SECRET_ACCESS_KEY].freeze

    # Командная строка работает локально, HTTP-сервер — через S3. Переменная
    # окружения перекрывает и то, и другое: RSOCKET_STORAGE=local выключает S3
    # совсем, и тогда сервер тоже работает с диском.
    # @param role [Symbol] :cli или :http
    # @param env [Hash]
    # @return [Storage]
    def self.for(role, env: ENV)
      new(kind: env.fetch("RSOCKET_STORAGE", role == :http ? S3 : LOCAL), env: env)
    end

    # @param kind [String] "local" или "s3"
    # @param env [Hash] откуда берём настройки хранилища
    # @raise [ArgumentError] вид хранилища неизвестен или S3 выбран, но не настроен
    def initialize(kind: LOCAL, env: ENV)
      @kind = kind.to_s
      @env = env
      raise ArgumentError, "неизвестное хранилище: #{@kind}. Известны: #{KINDS.join(", ")}" \
        unless KINDS.include?(@kind)

      check!
    end

    # @return [String] вид хранилища
    attr_reader :kind

    # @return [Boolean] работаем ли через S3
    def s3? = @kind == S3

    # @return [Repositories::Rules::Store] откуда берутся правила и профили
    def rules
      @rules ||= s3? ? Repositories::Rules::S3.new(client: client, prefix: prefix(:rules)) : local
    end

    # @return [Adapter::Upload::Store] куда складывается результат сборки
    def uploader
      @uploader ||= if s3?
                      Adapter::Upload::S3.new(client: client, prefix: prefix(:output))
                    else
                      Adapter::Upload::File.new
                    end
    end

    # @return [Adapter::S3::Client] клиент хранилища; поднимается только при s3
    def client
      @client ||= Adapter::S3::Client.new(
        endpoint: @env.fetch("RSOCKET_S3_ENDPOINT"), bucket: @env.fetch("RSOCKET_S3_BUCKET"),
        access_key_id: @env.fetch("RSOCKET_S3_ACCESS_KEY_ID"),
        secret_access_key: @env.fetch("RSOCKET_S3_SECRET_ACCESS_KEY"),
        region: @env.fetch("RSOCKET_S3_REGION", "us-east-1")
      )
    end

    # @return [String] чем хранилище представляется в сводке и в логе запуска
    def to_s = "#{@kind}: правила — #{rules}, результат — #{uploader}"

    private

    # @return [Repositories::Rules::Local]
    def local = @local ||= Repositories::Rules::Local.new

    # @param section [Symbol] :rules или :output
    # @return [String] префикс ключей этого раздела
    def prefix(section)
      @env.fetch("RSOCKET_S3_#{section.to_s.upcase}_PREFIX", section.to_s)
    end

    # Настройки проверяем на старте, а не на первом запросе: неполный конфиг
    # должен ронять запуск сразу и с перечислением того, чего не хватает.
    # @return [void]
    # @raise [ArgumentError] выбран S3, но настроек нет
    def check!
      return unless s3?

      missing = REQUIRED.select { |name| @env[name].to_s.empty? }
      return if missing.empty?

      raise ArgumentError, "для хранилища s3 не заданы: #{missing.join(", ")}. " \
                           "Либо задайте их, либо выберите local"
    end
  end
end
