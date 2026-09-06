# frozen_string_literal: true

RSpec.describe Repositories::Rules::Local do
  subject(:store) { described_class.new(root: root) }

  let(:root) { Pathname.new(Dir.mktmpdir) }

  it "хранит и отдаёт содержимое" do
    store.write("contracts/demo/contract.yml", "contract:\n")
    expect(store.read("contracts/demo/contract.yml")).to eq("contract:\n")
  end

  it "создаёт вложенные каталоги при записи" do
    expect { store.write("contracts/demo/service.rb.erb", "шаблон") }
      .to change { store.exist?("contracts/demo/service.rb.erb") }.from(false).to(true)
  end

  it "перечисляет ключи от корня хранилища" do
    store.write("base.yml", "archetypes:\n")
    store.write("contracts/demo/contract.yml", "contract:\n")
    expect(store.list).to eq(%w[base.yml contracts/demo/contract.yml])
  end

  it "показывает только запрошенную часть" do
    store.write("base.yml", "archetypes:\n")
    store.write("contracts/demo/contract.yml", "contract:\n")
    expect(store.list("contracts/")).to eq(%w[contracts/demo/contract.yml])
  end

  it "объясняет, если файла нет" do
    expect { store.read("нетакого.yml") }.to raise_error(ArgumentError)
  end

  # Ключ приходит снаружи: за пределы корня выйти нельзя.
  it "не выпускает за пределы корня" do
    expect { store.read("contracts/../../etc/passwd") }
      .to raise_error(ArgumentError, /за пределы хранилища/)
  end

  it "не принимает ключ странного вида" do
    expect { store.write(".ssh/id_rsa", "нет") }
      .to raise_error(ArgumentError, /недопустимый ключ/)
  end
end
