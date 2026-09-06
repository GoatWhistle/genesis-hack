# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Параметр нового ресурса отличаем от параметров родителя/продукта по пути
      # выбранного создания. Имя code или payout само по себе ничего не доказывает.
      module ResourceParameters
        module_function

        def identifier(create, operation)
          return nil if create.nil? || operation.nil? || create.equal?(operation)

          branch = Classification::Coherence.resource_branch(create.path)
          other = Classification::Coherence.resource_branch(operation.path)
          return nil unless other == branch + ["{}"]

          operation.path.scan(/\{([^}]+)\}/).last&.first
        end
      end
    end
  end
end
