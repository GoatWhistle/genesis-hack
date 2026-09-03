# frozen_string_literal: true

require "erb"

require_relative "context_builder"
require_relative "rubocop_pass"
require_relative "template_binding"

module Rsocket
  module Generate
    # Сборка сервиса интеграции по описанию API.
    #
    # Порядок работы обратный интуитивному и это принципиально: сначала был
    # написан руками образец в reference/, потом из него родился шаблон.
    # Генератор только подставляет в шаблон готовые значения и прогоняет
    # результат через линтер.
    class ServiceGenerator
      TEMPLATE = File.expand_path("../templates/service.rb.erb", __dir__)

      Result = Data.define(:filename, :source, :context, :lint) do
        def notes
          context.notes
        end
      end

      def initialize(spec, provider:, classification: nil, linter: RubocopPass.new)
        @spec = spec
        @classification = classification
        @provider = provider
        @linter = linter
      end

      def call
        context = ContextBuilder.new(@spec, provider: @provider,
                                            classification: @classification).call
        filename = "#{context.provider}_service.rb"
        lint = @linter.call!(render(context), filename: filename)
        Result.new(filename: filename, source: lint.source, context: context, lint: lint)
      end

      private

      # trim_mode "-" включает `<%-` и `-%>`: без них каждая строка с условием
      # оставляла бы в результате пустую строку, и файл выглядел бы дырявым.
      def render(context)
        template = ERB.new(File.read(TEMPLATE), trim_mode: "-")
        template.result(TemplateBinding.new(context).erb_binding)
      end
    end
  end
end
