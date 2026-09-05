# frozen_string_literal: true

RSpec.describe Config::Storage do
  let(:s3_env) do
    { "RSOCKET_S3_ENDPOINT" => "http://minio:9000", "RSOCKET_S3_BUCKET" => "rsocket",
      "RSOCKET_S3_ACCESS_KEY_ID" => "key", "RSOCKET_S3_SECRET_ACCESS_KEY" => "secret" }
  end

  describe "локальное хранилище" do
    subject(:storage) { described_class.new(kind: "local", env: {}) }

    it "берёт правила с диска" do
      expect(storage.rules).to be_a(Repositories::Rules::Local)
    end

    it "складывает результат в каталог" do
      expect(storage.uploader).to be_a(Adapter::Upload::File)
    end

    # Без единой настройки S3 инструмент обязан работать целиком.
    it "не требует ни одной настройки S3" do
      expect { storage.rules }.not_to raise_error
    end
  end

  describe "S3" do
    subject(:storage) { described_class.new(kind: "s3", env: s3_env) }

    it "берёт правила из бакета" do
      expect(storage.rules).to be_a(Repositories::Rules::S3)
    end

    it "складывает результат туда же" do
      expect(storage.uploader).to be_a(Adapter::Upload::S3)
    end

    it "называет, где что лежит" do
      expect(storage.to_s).to include("s3://rsocket/rules", "s3://rsocket/output")
    end

    it "разделяет правила и результат префиксами" do
      expect(storage.uploader.to_s).not_to eq(storage.rules.to_s)
    end
  end

  describe "когда S3 выбран, но не настроен" do
    subject(:storage) { described_class.new(kind: "s3", env: s3_env.except("RSOCKET_S3_BUCKET")) }

    # Неполный конфиг должен ронять запуск сразу, а не первый запрос.
    it "не даёт запуститься и называет, чего не хватает" do
      expect { storage }.to raise_error(ArgumentError, /RSOCKET_S3_BUCKET/)
    end

    it "подсказывает, что можно обойтись локальным хранилищем" do
      expect { storage }.to raise_error(ArgumentError, /выберите local/)
    end
  end

  describe "выбор при запуске" do
    it "командной строке даёт локальное хранилище" do
      expect(described_class.for(:cli, env: {}).kind).to eq("local")
    end

    it "серверу — S3" do
      expect(described_class.for(:http, env: s3_env).kind).to eq("s3")
    end

    # S3 можно выключить совсем: тогда и сервер работает с диском.
    it "уважает выключенный S3" do
      expect(described_class.for(:http, env: { "RSOCKET_STORAGE" => "local" }).kind).to eq("local")
    end

    it "не знает других хранилищ" do
      expect { described_class.new(kind: "ftp", env: {}) }
        .to raise_error(ArgumentError, /неизвестное хранилище: ftp/)
    end
  end
end
