# frozen_string_literal: true

RSpec.describe Adapter::Upload::File do
  subject(:uploader) { described_class.new(root: root) }

  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:files) { { "novapay_service.rb" => "# сервис\n", "mapping.yml" => "provider: novapay\n" } }

  it "раскладывает результат по разделу провайдера" do
    uploader.store("novapay", files)
    expect(root.join("novapay", "novapay_service.rb").read).to eq("# сервис\n")
  end

  it "говорит, куда именно всё легло" do
    expect(uploader.store("novapay", files))
      .to contain_exactly(a_string_ending_with("novapay/novapay_service.rb"),
                          a_string_ending_with("novapay/mapping.yml"))
  end

  it "создаёт каталог, если его ещё нет" do
    expect { uploader.store("swiftpay", files) }.to change { root.join("swiftpay").exist? }
      .from(false).to(true)
  end

  it "называет себя в сводке" do
    expect(uploader.to_s).to include(root.to_s)
  end
end
