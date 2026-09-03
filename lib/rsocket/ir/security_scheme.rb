# frozen_string_literal: true

module Rsocket
  module Ir
    SecurityScheme = Data.define(:id, :kind, :location, :name, :description) do
      def initialize(**attributes)
        defaults = { location: nil, name: nil, description: nil }
        super(**defaults.merge(attributes))
      end
    end
  end
end
