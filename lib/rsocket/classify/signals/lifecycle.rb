# frozen_string_literal: true

require_relative "../evidence"
require_relative "../meanings"

module Rsocket
  module Classify
    module Signals
      # Признак «по связям через идентификаторы».
      #
      # Самый устойчивый из трёх: он не читает ни одного слова, придуманного
      # провайдером, — только строение адресов. Если по адресу /ресурс приходит
      # ответ с идентификатором, а рядом есть /ресурс/{идентификатор}, то первая
      # операция создаёт, а вторая читает. Это верно и для описания на языке,
      # которого мы не знаем.
      class Lifecycle
        SIGNAL = :lifecycle

        RULES = %i[issues_identifier consumes_identifier reads_without_body].freeze

        SUCCESS_CODES = (200..299)

        def initialize(context)
          @weights = context.dictionaries.weights["lifecycle"] || {}
          @meanings = Meanings.new(context.dictionaries.fields)
          @paths = context.spec ? context.spec.operations.map(&:path).uniq : []
        end

        def evidence(operation, role)
          (role.rules & RULES).filter_map { |rule| entry(rule, operation) }
        end

        private

        def entry(rule, operation)
          detail = send(rule, operation)
          return if detail.nil?

          Evidence.new(signal: SIGNAL, detail: detail, weight: weight(rule))
        end

        def weight(rule) = (@weights[rule.to_s] || 0.0).to_f

        # Операция выдаёт идентификатор, который другие принимают в пути, —
        # значит ресурс появляется здесь.
        def issues_identifier(operation)
          identifier = @meanings.find(response_fields(operation), :identifier)
          return if identifier.nil?

          consumers = children_of(operation.path)
          return if consumers.empty?

          "ответ содержит идентификатор «#{identifier.path}», а по адресу " \
            "«#{consumers.first}» его принимают другие операции"
        end

        # Обратная сторона той же связи: адрес операции продолжает адрес,
        # по которому ресурс создаётся.
        def consumes_identifier(operation)
          parent = parent_of(operation.path)
          return if parent.nil? || !@paths.include?(parent)

          "адрес продолжает «#{parent}» идентификатором ранее созданного ресурса"
        end

        def reads_without_body(operation)
          return unless operation.http_method == :get && operation.request_fields.empty?
          return if consumes_identifier(operation).nil?

          "ресурс читается по идентификатору и без тела запроса"
        end

        # Адреса вида «/ресурс/{...}»: продолжения этого адреса параметром.
        def children_of(path)
          @paths.select { |candidate| candidate.start_with?("#{path}/{") }
        end

        # Адрес до первого параметра: для /v1/transfers/{transferNo}/abort это
        # /v1/transfers.
        def parent_of(path)
          segments = path.split("/")
          index = segments.index { |segment| segment.start_with?("{") }
          return if index.nil? || index.zero?

          segments.take(index).join("/")
        end

        def response_fields(operation)
          operation.responses.filter_map do |code, response|
            response.fields if code.is_a?(Integer) && SUCCESS_CODES.cover?(code)
          end.flatten
        end
      end
    end
  end
end
