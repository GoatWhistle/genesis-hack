# frozen_string_literal: true

module Rsocket
  module Ir
    Response = Data.define(:code, :description, :fields, :examples, :headers) do
      def initialize(**attributes)
        defaults = { description: nil, fields: [], examples: {}, headers: [] }
        super(**defaults.merge(attributes))
      end
    end
  end
end
