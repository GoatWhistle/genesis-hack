# frozen_string_literal: true

module Rsocket
  module Ir
    Server = Data.define(:url, :description, :env) do
      def initialize(**attributes)
        defaults = { description: nil, env: :unknown }
        super(**defaults.merge(attributes))
      end
    end
  end
end
