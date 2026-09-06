# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Classification::Wording do
  describe ".role" do
    subject(:text) { described_class.role(rules.role(role_name)) }

    let(:role_name) { :create_request }

    it "начинается с названия роли" do
      expect(text).to start_with("создание выплаты")
    end

    it "объясняет словами, что роль значит для сценария" do
      expect(text).to include("отправляет такой запрос провайдеру", "выплата начинается")
    end

    it "перечисляет слова, которыми такую операцию называют" do
      expect(text).to include("create", "submit", "payout")
    end

    it "не тащит в текст обрывки регулярок по глаголу HTTP и форме пути" do
      expect(text).not_to include("post")
    end

    # Правило вида \A(?!.*refund).*payout перечисляет то, чем роль не является.
    it "не берёт слова из отрицательного просмотра" do
      role = rules.role(role_name)
      rule = Config::Rule.new(field: "method_name", pattern: '\A(?!.*возврат).*выплат', weight: 1)
      allow(role).to receive(:rules).and_return(role.rules + [rule])
      expect(described_class.role(role)).not_to include("возврат")
    end

    describe "у роли, принимающей уведомление" do
      let(:role_name) { :process_callback }

      it "говорит, что запрос приходит к нам, а не от нас" do
        expect(text).to include("входящее уведомление")
      end
    end
  end

  describe ".operation" do
    subject(:text) { described_class.operation(operations_for("novapay").first) }

    it "называет операцию так же, как отчёт" do
      expect(text).to start_with("create_payout")
    end

    it "показывает адрес запроса" do
      expect(text).to include("POST /payouts")
    end

    it "оставляет слова автора описания" do
      expect(text).to include("выплат")
    end

    it "не разрастается на длинных описаниях" do
      expect(text.length).to be <= described_class::LIMIT
    end
  end
end
