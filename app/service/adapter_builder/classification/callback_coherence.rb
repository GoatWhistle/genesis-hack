# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Classification
      # Имена событий не REST-пути. Связь устанавливается по родителю callback
      # или явному ресурсу события/полей payload; совпадения слова webhook мало.
      module CallbackCoherence
        NOISE = ((Coherence::GENERIC - %w[payment transaction order]) +
                %w[webhook callback notification event notify on completed complete settled
                   failed success successful status changed updated processed]).freeze
        # Эти признаки разделяют потоки даже при общем слове payment/transfer.
        FLOWS = %w[payout transfer payment refund authorization authorisation payin incoming
                   link card batch ach wire book internal external received].freeze

        module_function

        def strength(origin, event)
          return 0 if origin.nil? || event.equal?(origin)
          return event.callback_origin.equal?(origin) ? 3 : 0 if event.callback_origin

          resource_strength(subject(origin), subject(event), event)
        end

        def resource_strength(source, target, event)
          return 0 if source.empty? || target.intersect?(FLOWS - source)
          return 2 if (source - target).empty?
          return 0 if target.intersect?(FLOWS)

          payload_strength(source, event)
        end

        # payout_id/transfer_id могут доказывать ресурс; id/status/amount — нет.
        def payload_strength(source, event)
          fields = Coherence.property_names(event.request_schema).flat_map do |name|
            Coherence.normalize(name)
          end
          source.intersect?(FLOWS) && (source - fields).empty? ? 1 : 0
        end

        def subject(operation)
          words = Coherence.normalize([operation.path, operation.operation_id,
                                       *operation.tags].join(" "))
          words.reject do |word|
            NOISE.include?(word) || Coherence::ACTIONS.include?(word) || Coherence::VERSION.match?(word)
          end.uniq
        end

        def explain(origin, event)
          if strength(origin, event) == 3
            "callback объявлен у выбранной операции создания"
          else
            "ресурс события или payload совпадает с потоком создания"
          end
        end
      end
    end
  end
end
