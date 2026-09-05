# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Analysis::StatusMapper do
  subject(:blueprint) { build_service(provider).blueprint }

  def mapped(blueprint)
    blueprint.status_map.transform_keys(&:downcase)
  end

  describe "на описании novapay" do
    let(:provider) { "novapay" }

    it "переводит состояния в статусы контракта" do
      expect(mapped(blueprint)).to eq("pending" => "in_progress", "processing" => "in_progress",
                                      "completed" => "approved", "failed" => "rejected",
                                      "cancelled" => "rejected")
    end

    it "переводит события webhook по последнему сегменту" do
      expect(blueprint.event_map).to include("payout.completed" => "approved",
                                             "payout.failed" => "rejected")
    end
  end

  describe "когда провайдер пишет состояния капсом" do
    let(:provider) { "nordbank" }

    it "всё равно их узнаёт" do
      expect(mapped(blueprint)).to include("executed" => "approved", "returned" => "rejected",
                                           "accepted" => "in_progress")
    end
  end

  describe "на описании swiftpay" do
    let(:provider) { "swiftpay" }

    it "узнаёт свои слова для тех же состояний" do
      expect(mapped(blueprint)).to eq("new" => "in_progress", "sent" => "in_progress",
                                      "paid" => "approved", "declined" => "rejected")
    end
  end

  describe "когда состояние лежит в конверте ответа" do
    let(:provider) { "kassabox" }

    it "запоминает путь до него целиком" do
      expect(blueprint.status_field).to eq(%w[data state])
    end
  end
end
