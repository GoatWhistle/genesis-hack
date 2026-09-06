# frozen_string_literal: true

RSpec.describe Service::AdapterBuilder::Classification::Coherence do
  def operation(id, method: :post, path: "/", responses: {})
    Models::ApiOperation.new(operation_id: id, http_method: method, path: path,
                             responses: responses)
  end

  # @return [Hash] ответ 200 со схемой из перечисленных свойств
  def answer(*names)
    { "200" => { description: "", schema: { properties: names.to_h { |name| [name, {}] } } } }
  end

  describe ".linked?" do
    it "связывает создание со статусом по тому же ресурсу и идентификатору" do
      create = operation("createPayout", path: "/v1/payouts", responses: answer(:id, :status))
      status = operation("getPayout", method: :get, path: "/v1/payouts/{payoutId}",
                                      responses: answer(:id, :status, :amount))

      expect(described_class).to be_linked(create, status)
    end

    it "связывает соседние действия одного раздела: create и get" do
      create = operation("createPayout", path: "/payouts/create", responses: answer(:id, :status))
      status = operation("getPayout", path: "/payouts/get", responses: answer(:id, :status))

      expect(described_class).to be_linked(create, status)
    end

    it "не считает доказательством общий префикс и слово payment" do
      create = operation("createPayment", path: "/api/v1/payments", responses: answer(:id))
      other = operation("getPaymentMethods", method: :get, path: "/api/v1/payment-methods",
                                             responses: answer(:methods))

      expect(described_class).not_to be_linked(create, other)
    end

    it "не связывает создание ACH с отменой телеграфного перевода" do
      create = operation("createAch", path: "/ach", responses: answer(:id, :status))
      cancel = operation("cancelWire", method: :patch, path: "/wires/{wire_id}",
                                       responses: answer(:id, :status))

      expect(described_class).not_to be_linked(create, cancel)
    end

    it "связывает создание с отменой на вложенном адресе" do
      create = operation("createTransfer", path: "/transfers", responses: answer(:id, :status))
      cancel = operation("cancelTransfer", path: "/transfers/{id}/cancel",
                                           responses: answer(:id, :status))

      expect(described_class).to be_linked(create, cancel)
    end
  end
end
