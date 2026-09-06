<p align="center">
  <img src="web/public/mark.svg" alt="" width="84" height="86"/>
</p>

<p align="center">
  <img src="web/public/wordmark.svg" alt="RSOCKET" width="240"/>
</p>

Инструмент читает описание API платёжного провайдера в формате OpenAPI и собирает по нему
интеграцию: сервис на Ruby по контракту заказчика, инструкцию по подключению, примеры
запросов и ответов, отчёт о принятых решениях.

Инструмент определяет, какая операция создаёт выплату, какие состояния означают успех,
какие ошибки допускают повтор, в каких единицах передаётся сумма. Решения, принятые с
неполными данными, перечисляются в отчёте и в выводе команды.

## Результат сборки

Одна сборка — четыре файла в `output/<провайдер>/`:

| Файл                     | Содержимое                                                            |
| ------------------------ | --------------------------------------------------------------------- |
| `<провайдер>_service.rb` | сервис по контракту заказчика: запросы, статусы, ошибки, webhook      |
| `INTEGRATION.md`         | инструкция: настройка, авторизация, методы, маппинг статусов, ошибки  |
| `fixtures.json`          | примеры запросов, ответов по кодам и входящих уведомлений             |
| `mapping.yml`            | разбор описания: роли, счёт, правила, единицы суммы, итог проверки    |

`mapping.yml` предназначен для ручной проверки принятых решений.

## Установка

Требуется Ruby 3.3.12 — версия указана в `.ruby-version`.

```
brew install ruby@3.3
export PATH="/opt/homebrew/opt/ruby@3.3/bin:$PATH"
```

С rbenv версия читается из `.ruby-version`: `rbenv install 3.3.12`.

Зависимости:

```
gem install bundler
bundle install
```

Используются `thor` (командная строка), `rack`, `rackup`, `webrick` (HTTP-режим), `rspec`,
`rubocop`, `webmock` (проверки).

## Команды Makefile

Список печатает `make help`:

| Команда                     | Действие                                                |
| --------------------------- | ------------------------------------------------------- |
| `make install`              | установить гемы                                         |
| `make check`                | тесты и линтер                                          |
| `make build PROVIDER=novapay` | собрать интеграцию по `examples/<провайдер>/`         |
| `make examples`             | собрать все четыре примера                              |
| `make serve PORT=8080`      | поднять HTTP-сервер локально, без S3                    |
| `make request`              | отправить описание на поднятый сервер и разложить ответ |
| `make up`, `make down`      | стек в контейнерах: MinIO и сервер                      |
| `make clean`                | очистить `output/`                                      |

Переменные `PROVIDER`, `SPEC`, `CONTRACT`, `OUT`, `HOST`, `PORT`, `STORAGE`
переопределяются в командной строке: `make build PROVIDER=kassabox CONTRACT=plain_client`.

## Проверка установки

```
bundle exec rspec      # 404 примера: разбор, классификация, печать, HTTP, сгенерированный сервис
bundle exec rubocop    # линтер
```

Два набора проверок работают с собранным кодом, а не с внутренними структурами.
`spec/integration/generated_service_spec.rb` собирает сервис, загружает его как обычный
файл и проверяет через `webmock` отправленный запрос. `spec/integration/tester_spec.rb`
проверяет саму процедуру проверки: часть примеров вносит в собранный сервис ошибку
(неверный адрес, потерянное поле, испорченная карта статусов) и требует, чтобы она была
обнаружена.

Текущее состояние правил:

```
bundle exec bin/rsocket doctor
```

```
контракт: space_payments — контракт Space Payments (Provider::BaseService)
правила:  локальный каталог <репозиторий>/app/config/rules
  create_request     порог 13, обязательна,    правил: 11, calls_provider creates_operation
  fetch_status       порог 14, обязательна,    правил: 10, calls_provider
  process_callback   порог  8, необязательна,  правил: 5, receives_callback
  cancel_request     порог 14, необязательна,  правил: 8, calls_provider
```

## Два способа запуска

Оба способа используют один и тот же менеджер сборок и на одном описании дают одинаковые
файлы. Различаются источник описания и место результата.

|                     | Командная строка                          | HTTP-сервер                                              |
| ------------------- | ----------------------------------------- | -------------------------------------------------------- |
| команда             | `bin/rsocket build`                       | `bin/rsocket serve`, затем `POST /build`                 |
| источник описания   | файл на диске                             | тело запроса                                             |
| источник правил     | `app/config/rules/`                       | те же файлы или бакет S3                                 |
| результат           | файлы в `output/<провайдер>/`             | JSON с содержимым файлов, плюс они же на диске или в S3  |
| назначение          | разовая сборка и разбор отчёта            | встраивание в пайплайн, изменение правил без перезапуска |

S3 в обоих режимах опционален.

## Запуск: командная строка

```
bundle exec bin/rsocket build --spec examples/novapay/provider_api.yaml --provider novapay
```

```
контракт: space_payments
  create_request     POST /payouts
  fetch_status       GET /payouts/{payout_id}
  process_callback   POST /webhooks/payout
  cancel_request     POST /payouts/{payout_id}/cancel
  ! сумма провайдера: amount (integer), единицы: копейки
  ! подпись приходит в заголовке X-NovaPay-Signature
проверка: проверок: 28, прошло: 28, не прошло: 0

  output/novapay/novapay_service.rb
  output/novapay/INTEGRATION.md
  output/novapay/fixtures.json
  output/novapay/mapping.yml
```

Первый блок — распределение эндпоинтов по ролям. Строки с `!` — решения, требующие
проверки, и неподдержанные конструкции. Роль без подходящей операции печатается как
`заглушка`; в сгенерированном сервисе соответствующий метод возвращает отказ. Отсутствие
обязательной роли прерывает сборку с указанием, каких ролей не хватило.

Последняя строка — итог проверки собранного класса, см. раздел «Проверка собранного
класса».

Флаги:

| Флаг               | Значение                                                         | По умолчанию      |
| ------------------ | ---------------------------------------------------------------- | ----------------- |
| `-s`, `--spec`     | путь к описанию OpenAPI (YAML или JSON)                          | обязателен        |
| `-p`, `--provider` | имя провайдера: определяет имя класса, файла и переменных окружения | обязателен     |
| `-o`, `--out`      | каталог результата                                               | `output`          |
| `-c`, `--contract` | профиль контракта                                                | `space_payments`  |
| `--storage`        | источник правил и место результата: `local` или `s3`             | `local`           |
| `--no-test`        | не проверять собранный класс в конце сборки                      | проверка включена |

`--provider novapay` даёт класс `Provider::NovapayService`, файл `novapay_service.rb` и
переменные `NOVAPAY_BASE_URL`, `NOVAPAY_API_KEY`, `NOVAPAY_CALLBACK_SECRET`.

## Поддерживаемые конструкции описаний

В `examples/` четыре описания с разными именами операций, вложенностью полей, единицами
суммы и способами авторизации. Собираются все:

```
for p in novapay kassabox nordbank swiftpay; do
  bundle exec bin/rsocket build -s examples/$p/provider_api.yaml -p $p
done
```

| Пример     | Особенности                                                                                                                             |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `novapay`  | СБП-выплаты, сумма в копейках, ключ в заголовке, webhook с HMAC-подписью                                                                |
| `kassabox` | конверт `data.*` в ответе, поля `orderNo`/`sum.value`/`payee.cardToken`, свой заголовок идемпотентности, две схемы авторизации          |
| `nordbank` | сумма строкой в рублях, `oneOf` в реквизитах получателя, состояния в верхнем регистре, `securitySchemes` отсутствует                    |
| `swiftpay` | сумма числом в рублях, Bearer-токен, webhook не описан — статус определяется опросом                                                    |

Конструкции, отсутствующие в описании, не достраиваются: в `nordbank` метод `authorize`
печатается с TODO и пояснением, в `swiftpay` `process_callback` возвращает отказ
`callback_not_supported`. Все такие случаи попадают в строки с `!` и в `mapping.yml`.

## Что инструмент вычитывает из описания

| Что | Откуда берётся | Куда попадает |
| --- | --- | --- |
| методы API | `paths`, `operationId`, `summary`, `tags` | роли контракта, таблица методов в `INTEGRATION.md` |
| параметры запроса | схема `requestBody`, `parameters` пути и строки запроса | тело запроса и его сборка в сервисе |
| поля ответа | схемы ответов `2xx`, включая конверты вида `data.*` | чтение идентификатора операции и состояния |
| авторизация | `securitySchemes`, `security` | заголовок или строка запроса, переменные окружения, раздел «Авторизация» |
| состояния операций | `enum` полей состояния, примеры ответов | `STATUS_MAP` и таблица маппинга статусов |
| ошибки | ответы `4xx`/`5xx` и их схемы | `ERROR_MAP`, `ERROR_ACTIONS`, таблица обработки ошибок |
| уведомления | `webhooks`, операции приёма callback, заголовок подписи | `process_callback`, `EVENT_MAP`, проверка подписи |
| ограничения | `minimum`, `maximum`, `enum`, `required`, форматы и единицы суммы | предпроверки в `check_conditions` |
| идемпотентность | заголовки вида `Idempotency-Key` | заголовки исходящего запроса |

Всё, что не удалось вывести однозначно, печатается строкой с `!` и записывается в
`mapping.yml` — решение не подставляется молча.

## Что получается на выходе

Фрагменты настоящего результата сборки `novapay`.

Карты статусов и ошибок собраны из описания, а не написаны руками:

```ruby
STATUS_MAP = {
  "cancelled" => "rejected", "completed" => "approved", "failed" => "rejected",
  "pending" => "in_progress", "processing" => "in_progress"
}.freeze

ERROR_MAP = {
  400 => %i[validation_error bad_request], 401 => %i[invalid_credentials unauthorized],
  402 => %i[insufficient_balance payment_required], 429 => %i[rate_limit too_many_requests],
  500 => %i[internal_error internal_server_error],
  default: %i[unknown_error bad_gateway]
}.freeze

# Что делать с ошибкой: reject — операция не пройдёт, retry* — можно повторить.
ERROR_ACTIONS = { "rate_limit" => "retry_backoff", "insufficient_balance" => "retry_later",
                  "invalid_credentials" => "alert", "validation_error" => "reject" }.freeze

# Источник: minimum у поля amount в схеме запроса.
MIN_AMOUNT = 1000
# Источник: enum поля currency в схеме запроса.
ALLOWED_CURRENCIES = %w[RUB].freeze
```

Методы контракта. Над каждым — откуда взялась роль:

```ruby
# Создание выплаты: POST /payouts (create_payout).
# роль назначена: счёт 22 при пороге 13 по полям method_name, path, http_method,
# summary, структура. Разбор — в mapping.yml.
def create_request(operation, request_method = "create")
  response = request(:post, "/payouts", body: create_request_body(operation),
                     headers: { "Idempotency-Key" => operation.id })
  return handle_error(response) unless response.success?

  identifier = dig_body(response.body, "id")
  return failure(:bad_gateway, "provider.missing_operation_id") unless valid_identifier?(identifier)

  operation.provider_operation_id = identifier
  success
rescue MissingParameter
  failure(:unprocessable_entity, "provider.missing_parameter")
end

def process_callback(payload)
  return failure(:unauthorized, "provider.invalid_signature") unless valid_signature?(payload)

  operation_id = dig_body(payload, "payout_id")

  case callback_status(payload)
  when "approved" then approve_operation(operation_id)
  when "rejected" then reject_operation(operation_id, callback_error(payload))
  when "in_progress" then success
  else failure(:unprocessable_entity, "unknown_event")
  end
end

def check_conditions(operation, request_method)
  result = super
  return result if result.failed?

  return failure(:unprocessable_entity, "amount_too_low") if operation.amount < MIN_AMOUNT
  return failure(:unprocessable_entity, "unsupported_currency") unless ALLOWED_CURRENCIES.include?(operation.currency.to_s)

  success
end
```

Адрес, ключи и таймауты вынесены в переменные окружения: `NOVAPAY_BASE_URL`,
`NOVAPAY_API_KEY`, `NOVAPAY_CALLBACK_SECRET`.

`INTEGRATION.md` — настройка, авторизация, методы, статусы, ошибки:

```
## Авторизация
- Тип: **api_key** (схема `ApiKeyAuth` из описания)
- Куда: заголовок `X-API-Key`

## Методы
| Метод контракта  | Endpoint                        | Назначение        | Заголовки       |
| create_request   | POST /payouts                   | создание выплаты  | Idempotency-Key |
| fetch_status     | GET /payouts/{payout_id}        | статус-запрос     |                 |
| process_callback | POST /webhooks/payout           | обработка webhook |                 |

## Маппинг статусов
| pending | in_progress |  | completed | approved |  | failed | rejected |

Состояние, отсутствующее в таблице, интерпретируется как `in_progress`: закрытие
операции по нераспознанному значению приводит к потере данных, повторный запрос — нет.
```

`fixtures.json` — примеры запроса, ответов по кодам и входящих уведомлений:

```json
{
  "create_request": {
    "endpoint": "POST /payouts",
    "request": { "amount": 1500000, "currency": "RUB", "external_id": "op_abc123",
                 "recipient": { "type": "sbp", "phone": "79001234567", "bank_code": "044525225" } },
    "responses": {
      "201": { "id": "np_7f3a9b2c", "status": "pending" },
      "402": { "error": { "code": "insufficient_balance" } }
    },
    "response_headers": { "429": { "retry-after": 1 } }
  }
}
```

## Ошибки разбора и сборки

Инструмент не падает трассировкой: причина печатается строкой, код возврата ненулевой.

```
не собралось: описание API не найдено: /путь/nope.yaml
не собралось: не разобрать YAML: did not find expected ',' or ']' at line 1 column 6
не собралось: описание не OpenAPI/Swagger: нет ни paths, ни webhooks
```

Если описание разобрано, но обязательной роли нет, сборка прерывается с указанием,
каких ролей не хватило. Необязательная роль без кандидата печатается как `заглушка`,
и соответствующий метод сгенерированного сервиса возвращает отказ. В HTTP-режиме те же
случаи возвращаются JSON-ом: **400** — некорректный запрос, **422** — описание разобрано,
но не пригодно для сборки.

## Проверка на чужих описаниях

Правила составлялись не по четырём примерам из `examples/`. Замер идёт на 71 стороннем
описании настоящих провайдеров — Stripe, Adyen, PayPal, Plaid, Wise, Open Banking UK,
Modern Treasury и других. Список источников и скрипт загрузки лежат в `bench/`
(в репозиторий не входят: часть описаний без лицензии, вместе 17 МБ).

| корпус | описаний | прочитано | верных назначений ролей |
| --- | --- | --- | --- |
| `bench/truth.yml` | 47 | 47 | 163 из 188 |
| `bench/truth-new.yml` | 24 | 20 | 51 из 80 |

Верным считается и отказ: если провайдер не описывает отмену или webhook, правильный
ответ — оставить роль пустой, и это засчитывается. Четыре описания второго корпуса
внутри замера не читаются — известный дефект замерного скрипта, сами файлы инструмент
разбирает.

## Распределение ролей по операциям

Роль контракта — операция определённого назначения: создание выплаты, статус-запрос,
отмена, приём уведомления. Роли распределяются правилами со взвешенным счётом: правило
состоит из поля операции, регулярного выражения и веса. Роли обрабатываются в порядке из
конфигурации; операция, занятая одной ролью, в последующих не участвует; роль получает
операция с наибольшим счётом при условии, что счёт не меньше порога.

Веса разделяют признаки по значимости: `POST` встречается в большинстве операций,
слово `payout` в `operationId` — существенно реже. Правила `veto` исключают кандидата до
подсчёта очков: без них `cancelPayout` набрал бы очки как создание выплаты, поскольку это
`POST` со словом `payout` в имени.

Счёт, порог и сработавшие правила по каждой роли записываются в `mapping.yml`:

```yaml
  create_request:
    operation: create_payout
    endpoint: POST /payouts
    score: 22
    threshold: 13
    why: 'счёт 22 при пороге 13 по полям method_name, path, http_method, summary'
```

Новое написание `operationId` или новое название статуса добавляется правкой одной строки
в `base.yml` и действует для всех контрактов и провайдеров. Структура обоих файлов правил
описана в [docs/rules.md](docs/rules.md).

## Проверка собранного класса

Разбор и печать проверяют текст результата. Последняя ступень сборки проверяет поведение:
собранный класс загружается и вызывается.

Рядом со сборкой поднимается подставной провайдер на локальном порту. Адреса он берёт из
запланированных запросов, тела ответов — из описания провайдера, то есть отвечает теми же
примерами, что уходят в `fixtures.json`. Собранный класс загружается и вызывается по
ролям контракта: создание выплаты, запрос состояния, отмена, приём уведомления. На каждую
роль выполняется один прогон с успешным ответом и по одному прогону на каждый описанный
провайдером отказ.

Проверяется наблюдаемое поведение:

| Проверка | Способ |
| -------- | ------ |
| класс загружается и создаётся | исходник исполняется в отдельном модуле, имена контракта не занимаются глобально |
| запрос ушёл по нужному адресу и нужным глаголом | подставной провайдер записывает полученный запрос |
| запрос подписан | ключ ищется там, где его объявил провайдер: заголовок, `Authorization` или строка запроса |
| в теле присутствуют запланированные поля | тело сверяется с планом запроса |
| успешный ответ разобран как успех | роль вызывается на описанном ответе `2xx` |
| идентификатор операции прочитан из ответа | сверяется с примером ответа на создание |
| состояние переведено в статус контракта | состояние из примера ответа сверяется с картой статусов |
| отказ разобран нужным кодом | отдельный прогон на каждый описанный `4xx`/`5xx` |
| уведомление переведено в нужный статус | примеры webhook из фикстур сверяются с ожидаемым статусом |

Результат проверки не влияет на сборку: файлы к этому моменту напечатаны. Итог выводится
строкой в сводке и полностью записывается в `mapping.yml`:

```yaml
checks:
  passed: 28
  failed: 0
  notes: []
  checks:
    - role: create_request
      check: запрос уходит на POST /payouts
      ok: true
```

Подставной провайдер слушает `127.0.0.1`; внешние запросы не выполняются. Ключи
провайдера не требуются: в окружение записываются заведомо недействительные значения.

Способ вызова конкретного интерфейса задаёт профиль. Рядом с шаблонами лежит `probe.rb`:
он предоставляет недостающие зависимости и преобразует пару «роль, заявка» в вызов метода —
в `space_payments` это `Operation` и `Result`, в `plain_client` хеш платежа и исключение.
Профиль без `probe.rb` не проверяется; причина указывается в отчёте.

## Профили контрактов

Контракт заказчика задаётся профилем правил, а не кодом инструмента. Количество профилей
не ограничено:

```
bundle exec bin/rsocket contracts
```

```
  plain_client     обычный клиент на исключениях
* space_payments   контракт Space Payments (Provider::BaseService)
```

```
bundle exec bin/rsocket build -s examples/swiftpay/provider_api.yaml -p swiftpay \
                              --contract plain_client
```

По тому же описанию собирается класс с другими именами методов (`send_payout`,
`payout_state`, `read_callback`) и другой обработкой ошибок: это задаёт профиль, а не
разбор описания.

## Устройство

Разбор чужого API и описание контракта заказчика разделены: в правилах разбора нет имён
методов контракта, в профиле контракта нет имён провайдеров.

| Компонент               | Расположение                                  | Назначение                                                                            |
| ----------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------- |
| правила разбора         | `app/config/rules/base.yml`                   | как провайдеры называют операции, состояния, ошибки и поля                             |
| профили контрактов      | `app/config/rules/contracts/<профиль>/`       | `contract.yml` — роли, статусы, коды ошибок; рядом ERB-шаблоны и `probe.rb`            |
| разбор описания         | `app/service/adapter_builder/parsing/`        | чтение OpenAPI, раскрытие `$ref`, извлечение схем и примеров                           |
| распознавание ролей     | `app/service/adapter_builder/classification/` | сопоставление операций ролям со счётом и порогом                                       |
| решения о сборке        | `app/service/adapter_builder/analysis/`       | статусы, ошибки, тело запроса, единицы суммы, подпись webhook, предпроверки, фикстуры  |
| печать файлов           | `app/service/adapter_builder/rendering/`      | ERB-шаблоны профиля и отчёт                                                            |
| проверка собранного     | `app/service/adapter_builder/testing/`        | подставной провайдер, песочница, прогон ролей на фикстурах                              |
| командная строка и HTTP | `app/controller/`                             | слои над общим менеджером сборок                                                        |
| адаптеры и хранилища    | `app/adapter/`, `app/repositories/`           | чтение описания, запись результата, диск или S3                                         |

Классификатор подставляется через порт `Ports::Classifier`: сценарий сборки не зависит от
способа распределения ролей. Проверка подставляется через `Ports::Tester`; без неё сборка
завершается печатью файлов.

Новое написание `operationId` или новое название статуса добавляется правкой одной строки
в `base.yml` и действует для всех контрактов и провайдеров. Сборка под другой интерфейс
добавляется профилем в `contracts/`; код инструмента не изменяется. Структура обоих файлов
описана в [docs/rules.md](docs/rules.md).

## Запуск: HTTP-сервер

### Запуск сервера

```
bundle exec bin/rsocket serve --storage local
```

```
rsocket слушает http://127.0.0.1:9292
  GET  /             — что умеет сервис
  GET  /health       — жив ли он
  GET  /openapi.yaml — описание этого API
  GET  /contracts    — профили контрактов и их роли
  GET  /rules        — что лежит в хранилище правил
  PUT  /rules/<ключ> — записать правила или шаблон
  POST /build        — сборка: ?provider=имя[&contract=профиль][&test=1], тело — описание
хранилище: local: правила — локальный каталог <репозиторий>/app/config/rules, результат — каталог output
```

Флаг `--storage local` обязателен: у сервера, в отличие от командной строки, по умолчанию
выбрано S3. Без настроенного бакета сервер не запускается и перечисляет недостающие
переменные:

```
не поднялось: для хранилища s3 не заданы: RSOCKET_S3_ENDPOINT, RSOCKET_S3_BUCKET,
RSOCKET_S3_ACCESS_KEY_ID, RSOCKET_S3_SECRET_ACCESS_KEY. Либо задайте их, либо выберите local
```

Порт и адрес задаются флагами `--port` и `--host`. По умолчанию сервер слушает только
localhost; аутентификация не реализована.

### Сборка

Имя провайдера передаётся в строке запроса, описание — в теле. `Content-Type` не
учитывается: JSON определяется по первому символу, остальное читается как YAML.

```
curl -X POST "http://127.0.0.1:9292/build?provider=novapay" \
     --data-binary @examples/novapay/provider_api.yaml
```

```json
{
  "provider": "novapay",
  "contract": "space_payments",
  "warnings": ["сумма провайдера: amount (integer), единицы: копейки", "..."],
  "locations": ["output/novapay/novapay_service.rb", "..."],
  "files": { "novapay_service.rb": "# frozen_string_literal: true\n...", "...": "..." },
  "report": { "roles": { "create_request": { "endpoint": "POST /payouts", "score": 15 } } }
}
```

`warnings` — те же строки, что печатает командная строка после `!`; `report` — содержимое
`mapping.yml`; `files` — содержимое каждого файла строкой. Разложить их по файлам:

```
curl -s -X POST "http://127.0.0.1:9292/build?provider=novapay" \
     --data-binary @examples/novapay/provider_api.yaml \
| ruby -rjson -e 'JSON.parse($stdin.read)["files"].each { |name, body|
    File.write(name, body); puts name }'
```

Проверка собранного класса включается параметром `test=1`:

```
curl -X POST "http://127.0.0.1:9292/build?provider=novapay&test=1" \
     --data-binary @examples/novapay/provider_api.yaml
```

В ответе появляется поле `checks` с тем же содержимым, что уходит в `mapping.yml`. По
умолчанию проверка выключена: она исполняет сгенерированный код и поднимает локальный
сервер. В командной строке она включена по умолчанию и выключается флагом `--no-test`.

Ошибки возвращаются JSON-ом с полем `error`: **400** — некорректный запрос (нет
`provider`, пустое или неразобранное тело), **422** — описание разобрано, но не пригодно
для сборки; в тексте перечисляются недостающие роли.

### Запуск через rackup

`config.ru` находится в корне репозитория:

```
RSOCKET_STORAGE=local bundle exec rackup            # тот же сервис на 9292
RSOCKET_STORAGE=local bundle exec rackup -p 8080
```

### Запуск в контейнере

```
docker compose up --build      # MinIO + сервер на localhost:9292
docker compose down
```

Стек поднимает MinIO в роли S3-хранилища, переносит в бакет правила командой
`bin/rsocket push` и запускает сервер. Разовая сборка без сервера:

```
docker compose run --rm rsocket \
  bundle exec bin/rsocket build -s examples/novapay/provider_api.yaml -p novapay
```

### Переменные окружения

| Переменная                 | По умолчанию                     | Значение                       |
| -------------------------- | -------------------------------- | ------------------------------ |
| `RSOCKET_HOST`             | `127.0.0.1`                      | адрес, который слушает сервер  |
| `RSOCKET_PORT`             | `9292`                           | порт                           |
| `RSOCKET_STORAGE`          | `local` для CLI, `s3` для сервера | хранилище правил и результата  |
| `RSOCKET_CONTRACT`         | `space_payments`                 | профиль контракта по умолчанию |
| `RSOCKET_OUTPUT`           | `output`                         | каталог результата             |
| `RSOCKET_S3_*`             | —                                | endpoint, бакет и ключи S3     |

Полный список ручек, кодов ошибок и переменных — в [docs/http-api.md](docs/http-api.md);
там же описаны работа через S3 и изменение правил через `PUT /rules/<ключ>`.
Машиночитаемое описание — [docs/openapi.yaml](docs/openapi.yaml); сервис отдаёт его
ручкой `GET /openapi.yaml`.

## Витрина

Как инструмент разбирает чужое описание — видно вживую, без установки: операции
разбегаются по ролям, у каждой виден счёт при пороге и сработавшие правила, а
каждая строка собранного сервиса связана с решением, из которого выросла. Своё
описание можно подсунуть прямо на сайте — оно уходит в настоящий `POST /build`.

Адрес: **https://genesis.goatwhistle.ru**

Пять страниц: главная с полным проходом данных, разбор описания, правила с
песочницей, сравнение четырёх провайдеров и документация. Без сервера сайт тоже
работает — разборы запечены в сборку дословными ответами сервиса.

Исходники — в каталоге [web/](web/). Это отдельная от решения часть: ни один
Ruby-файл от неё не зависит. Как запустить — [web/README.md](web/README.md),
как развернуть — [web/infra/DEPLOY.md](web/infra/DEPLOY.md).
