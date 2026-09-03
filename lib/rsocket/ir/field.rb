# frozen_string_literal: true

module Rsocket
  module Ir
    Field = Data.define(
      :name, :type, :format, :description, :required, :enum, :pattern,
      :minimum, :maximum, :max_length, :example, :children, :item, :path
    ) do
      def initialize(**attributes)
        defaults = {
          type: nil, format: nil, description: nil, required: false, enum: nil,
          pattern: nil, minimum: nil, maximum: nil, max_length: nil, example: nil,
          children: [], item: nil, path: nil
        }
        super(**defaults.merge(attributes))
      end
    end
  end
end
