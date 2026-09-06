# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Adapter
  # Превращение текста в вектор. Своего API эмбеддингов у Anthropic нет, поэтому
  # это единственное место, где мы ходим не к Claude.
  module Embedding
    # Клиент Voyage AI на стандартной библиотеке — по тем же соображениям, что и
    # клиент S3: ради одного POST тянуть SDK незачем.
    #
    # Почему Voyage и почему voyage-3.5-lite: Voyage — рекомендованный Anthropic
    # партнёр по эмбеддингам, а младшая модель линейки 3.5 мультиязычная. Это
    # здесь главное: описания провайдеров написаны русским вперемешку с
    # английским («Создать выплату» рядом с createPayout), и одноязычная модель
    # половину признаков просто не увидит. Старшие модели той же линейки на
    # тексте в две строки не дают ничего, кроме счёта и задержки.
    class Voyage
      include Service::AdapterBuilder::Ports::Embedder

      ENDPOINT = "https://api.voyageai.com/v1/embeddings"
      DEFAULT_MODEL = "voyage-3.5-lite"
      KEY = "VOYAGE_API_KEY"
      # Voyage принимает до 1000 текстов за запрос; столько нам не нужно, но
      # ограничение объявляем явно — в большом описании операций бывает много.
      BATCH = 128
      # Коды, после которых имеет смысл повторить: лимит и временные отказы.
      RETRIABLE = %w[429 500 502 503 504].freeze
      # Пауза перед повтором удваивается с каждой попыткой. Секунды здесь не от
      # осторожности: на бесплатном тарифе Voyage считает запросы штуками в
      # минуту, и повтор через полсекунды упирается в тот же отказ.
      BACKOFF = 2.0

      # Voyage ответил не тем, чего мы ждали.
      class Error < StandardError; end

      # @param api_key [String, nil] ключ Voyage
      # @param model [String] имя модели эмбеддингов
      # @param attempts [Integer] сколько раз пробуем при временном отказе
      # @param open_timeout [Integer]
      # @param read_timeout [Integer]
      def initialize(api_key: ENV.fetch(KEY, nil), model: ENV.fetch("VOYAGE_MODEL", DEFAULT_MODEL),
                     attempts: 5, open_timeout: 5, read_timeout: 30)
        @api_key = api_key
        @model = model
        @attempts = attempts
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      attr_reader :model

      # @param texts [Array<String>] тексты одной пачкой
      # @return [Array<Array<Float>>] векторы в том же порядке
      # @raise [Error] ключа нет или Voyage ответил ошибкой
      def embed(texts)
        raise Error, "не задан #{KEY}" if @api_key.to_s.empty?
        return [] if texts.empty?

        texts.each_slice(BATCH).flat_map { |batch| vectors_of(request(batch)) }
      end

      # @return [String] чем считали — уходит в отчёт и в бенчмарк
      def to_s = "voyage/#{@model}"

      private

      # @param body [Hash] разобранный ответ
      # @return [Array<Array<Float>>] векторы в порядке входных текстов
      def vectors_of(body)
        data = body["data"] or raise Error, "в ответе Voyage нет data: #{body.to_s[0, 200]}"
        data.sort_by { |item| item.fetch("index") }.map { |item| item.fetch("embedding") }
      end

      # input_type намеренно не задаём: он нужен, когда запрос и документ разной
      # природы. Наша задача симметричная — описание сравнивается с описанием.
      # @param batch [Array<String>]
      # @return [Hash] разобранный ответ
      # @raise [Error] попытки кончились или отказ не из временных
      def request(batch)
        response = attempt(JSON.generate(input: batch, model: @model))
        return JSON.parse(response.body) if response.code.start_with?("2")

        raise Error, "Voyage ответил #{response.code}: #{response.body.to_s[0, 300]}"
      end

      # @param payload [String] тело запроса
      # @return [Net::HTTPResponse] первый удачный ответ либо последний неудачный
      def attempt(payload)
        response = nil
        @attempts.times do |number|
          response = post(payload)
          return response if response.code.start_with?("2")
          return response unless RETRIABLE.include?(response.code)

          sleep(pause(response, number))
        end
        response
      end

      # Сколько ждать перед повтором: сервис вместе с отказом обычно называет
      # срок сам, и слушать его точнее, чем угадывать.
      # @param response [Net::HTTPResponse] отказ, который мы собираемся повторить
      # @param number [Integer] какая это по счёту неудача
      # @return [Float] секунды
      def pause(response, number)
        asked = response["retry-after"].to_f
        asked.positive? ? asked : BACKOFF * (2**number)
      end

      # @param payload [String] тело запроса
      # @return [Net::HTTPResponse]
      def post(payload)
        uri = URI.parse(ENDPOINT)
        request = Net::HTTP::Post.new(uri)
        request["authorization"] = "Bearer #{@api_key}"
        request["content-type"] = "application/json"
        request.body = payload
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: @open_timeout,
                                            read_timeout: @read_timeout) do |http|
          http.request(request)
        end
      end
    end
  end
end
