# frozen_string_literal: true

# Ошибки провайдера из системы заказчика.
#
# Откуда взято: в примере сгенерированного сервиса из задания встречаются
# `Provider::RateLimitError` и `Provider::UnauthorizedError`, перехватываемые
# прямо в теле метода. Самих классов нам не дали — эксперт подтвердил 3 сентября,
# что полный production-класс и обвязку выдавать не будут. Поэтому здесь наша
# реконструкция контракта: ровно те пять ошибок, что перечислены в задании,
# плюс два общих родителя, чтобы сервис мог поймать любую ошибку провайдера
# одним `rescue`, а не переписывать список из пяти веток в каждом методе.
class Provider
  # Общий предок всего, что может пойти не так на стороне провайдера.
  class Error < StandardError; end

  # Провайдер ответил, но ответ означает отказ.
  #
  # Несёт с собой всё, что нужно вызывающей стороне для решения: код ответа,
  # код ошибки самого провайдера и разобранное тело. Без этого сервису
  # пришлось бы разбирать тело второй раз, уже после перехвата.
  class ApiError < Error
    attr_reader :status, :provider_code, :body, :retry_after

    def initialize(message = nil, status: nil, provider_code: nil, body: nil, retry_after: nil)
      @status = status
      @provider_code = provider_code
      @body = body
      @retry_after = retry_after
      super(message || "провайдер ответил кодом #{status}")
    end
  end

  # Слишком много запросов. Если провайдер прислал заголовок с задержкой,
  # она лежит в `retry_after` — повтор без неё превращается в угадывание.
  class RateLimitError < ApiError; end

  # Ключ не принят: не передан, просрочен, отозван.
  class UnauthorizedError < ApiError; end

  # Провайдер отверг данные запроса. Повторять бессмысленно, пока не
  # изменится сам запрос.
  class ValidationError < ApiError; end

  # На балансе провайдера не хватает средств. Запрос корректен, повторять
  # имеет смысл позже.
  class InsufficientBalanceError < ApiError; end

  # Сбой на стороне провайдера. Повторяем и сообщаем дежурным.
  class InternalError < ApiError; end
end
