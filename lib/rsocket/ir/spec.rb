# frozen_string_literal: true

module Rsocket
  module Ir
    Spec = Data.define(
      :title, :version, :description, :servers, :security_schemes,
      :operations, :raw_schemas, :notes
    ) do
      def initialize(**attributes)
        defaults = {
          title: nil, version: nil, description: nil, servers: [], security_schemes: [],
          operations: [], raw_schemas: {}, notes: []
        }
        super(**defaults.merge(attributes))
      end
    end
  end
end
