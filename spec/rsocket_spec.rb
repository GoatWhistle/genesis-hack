# frozen_string_literal: true

# Смоук-тест сборки. Проверяет не логику, а то, что окружение поднялось:
# гем грузится, версия объявлена, корень репозитория находится оттуда,
# откуда бы команду ни запустили.
RSpec.describe Rsocket do
  describe "VERSION" do
    subject(:version) { described_class::VERSION }

    it { is_expected.to be_a(String) }

    it "выглядит как семвер" do
      expect(version).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe ".root" do
    subject(:root) { described_class.root }

    it "указывает на существующий каталог" do
      expect(File.directory?(root)).to be true
    end

    it "содержит точку входа lib/rsocket.rb" do
      expect(File.file?(File.join(root, "lib", "rsocket.rb"))).to be true
    end

    it "возвращает абсолютный путь" do
      expect(root).to eq(File.expand_path(root))
    end
  end
end
