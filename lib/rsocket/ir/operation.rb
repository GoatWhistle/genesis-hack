# frozen_string_literal: true

module Rsocket
  module Ir
    Operation = Data.define(
      :http_method, :path, :operation_id, :tags, :summary, :description,
      :path_params, :query_params, :header_params, :request_fields,
      :request_examples, :responses, :security
    ) do
      def initialize(**attributes)
        defaults = {
          operation_id: nil, tags: [], summary: nil, description: nil, path_params: [],
          query_params: [], header_params: [], request_fields: [], request_examples: {},
          responses: {}, security: []
        }
        super(**defaults.merge(attributes))
      end
    end
  end
end
