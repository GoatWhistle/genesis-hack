# frozen_string_literal: true

module Adapter
  module Loader
    # Описание, пришедшее не файлом, а текстом: телом HTTP-запроса, строкой из
    # очереди, куском из теста. Сценарий сборки разницы не видит — для него это
    # тот же порт SpecSource.
    module Text
      class SpecReader
        include Service::AdapterBuilder::Ports::SpecSource

        SOURCE = "тело запроса"
        JSON_START = "{"

        # @param reference [String] сам текст описания
        # @return [Hash] документ OpenAPI, ключи символами
        # @raise [ArgumentError] текст пуст, велик, не разобрался или не объект
        def read(reference)
          content = reference.to_s
          raise ArgumentError, "описание API пустое: #{SOURCE}" if content.strip.empty?

          Document.ensure_size(content.bytesize, SOURCE)
          Document.ensure_object(Document.parse(content, json: json?(content)), SOURCE)
        end

        private

        # Формат узнаём по первому непробельному символу: YAML разобрал бы и JSON,
        # но родной разборщик объясняет ошибку в JSON понятнее.
        # @param content [String]
        # @return [Boolean]
        def json?(content) = content.lstrip.start_with?(JSON_START)
      end
    end
  end
end
