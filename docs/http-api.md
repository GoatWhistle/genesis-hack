# HTTP API

HTTP-интерфейс к тому же менеджеру сборок, что используется в командной строке. Сервер
разбирает запрос, вызывает менеджер и возвращает результат в JSON. На одном описании
`bin/rsocket build` и `POST /build` дают одинаковые файлы.

Машиночитаемое описание API — [docs/openapi.yaml](openapi.yaml); сервис отдаёт его ручкой
`GET /openapi.yaml`.

Команды:

| Команда | Назначение |
|---|---|
| `bin/rsocket build` | одна сборка: правила с диска, файлы в `output/` |
| `bin/rsocket serve` | HTTP-сервер: правила и результат в S3 |
| `bin/rsocket push` | перенос локальных правил и шаблонов в S3 |
| `bin/rsocket contracts`, `doctor` | список профилей и правила разбора |

## Хранилища

Правила (`base.yml`, профили контрактов и их шаблоны) и результат сборки размещаются в
хранилище, которое выбирается при запуске:

| | Правила | Результат |
|---|---|---|
| `local` | каталог `app/config/rules/` | каталог `output/<provider>/` |
| `s3` | `s3://<бакет>/rules/` | `s3://<бакет>/output/<provider>/` |

Командная строка по умолчанию работает локально, сервер — через S3. Оба умолчания
переопределяются флагом `--storage` или переменной `RSOCKET_STORAGE`.

S3 не обязателен: с `RSOCKET_STORAGE=local` сервер работает с диском и не требует
дополнительной настройки. Если S3 выбран, но не настроен, сервер не запускается и
перечисляет недостающие переменные.

Правила читаются на каждый запрос, поэтому изменение действует немедленно — и при правке
файла на диске, и при записи через `PUT /rules/<ключ>`.

---

## Быстрый старт

```
bundle exec bin/rsocket serve
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
хранилище: s3: правила — s3://rsocket/rules, результат — s3://rsocket/output
```

Первая сборка:

```
curl -X POST "http://127.0.0.1:9292/build?provider=novapay" \
     --data-binary @examples/novapay/provider_api.yaml
```

Через Docker:

```
docker compose up --build
curl -X POST "http://127.0.0.1:9292/build?provider=novapay" \
     --data-binary @examples/novapay/provider_api.yaml
```

---

## Запуск

### Локально

```
bundle exec bin/rsocket serve --storage local     # 127.0.0.1:9292, без S3
bundle exec bin/rsocket serve --port 8080         # другой порт
bundle exec bin/rsocket serve --host 0.0.0.0      # слушать все адреса
```

Без `--storage local` серверу требуется настроенный S3 — см. таблицу переменных ниже.

По умолчанию сервер слушает только localhost: аутентификация и ограничение частоты
запросов не реализованы.

### Через rackup

`config.ru` находится в корне репозитория, подойдёт любой сервер приложений:

```
bundle exec rackup                                # тот же сервис
bundle exec rackup -p 8080 -o 0.0.0.0
```

### В контейнере

```
docker compose up --build                         # MinIO + сервер на localhost:9292
docker compose logs -f rsocket                    # что происходит
docker compose down                               # остановить
```

Стек состоит из трёх частей: MinIO в роли S3-хранилища, разовый шаг `rules` (переносит
локальные правила в бакет командой `bin/rsocket push`) и сервер. Консоль MinIO доступна на
`localhost:9001`, логин и пароль — `rsocket` / `rsocket-secret`.

Разовая сборка без запуска сервера:

```
docker compose run --rm rsocket \
  bundle exec bin/rsocket build -s examples/novapay/provider_api.yaml -p novapay -o output
```

Каталог `output/` и каталог правил `app/config/rules/` смонтированы с хоста, изменения
видны контейнеру сразу. При работе через S3 правила читаются из бакета, куда попадают
командой `push` или записью через `PUT /rules/<ключ>`.

---

## Настройка

| Переменная | По умолчанию | Что задаёт |
|---|---|---|
| `RSOCKET_HOST` | `127.0.0.1` | адрес, который слушает сервер; в контейнере уже `0.0.0.0` |
| `RSOCKET_PORT` | `9292` | порт |
| `RSOCKET_CONTRACT` | `space_payments` | профиль контракта по умолчанию |
| `RSOCKET_STORAGE` | `local` для CLI, `s3` для сервера | какое хранилище использовать |
| `RSOCKET_RULES_ROOT` | `app/config/rules` | каталог с правилами при локальном хранилище |
| `RSOCKET_OUTPUT` | `output` | каталог результата при локальном хранилище |
| `RSOCKET_S3_ENDPOINT` | — | адрес хранилища, например `http://minio:9000` |
| `RSOCKET_S3_BUCKET` | — | имя бакета |
| `RSOCKET_S3_ACCESS_KEY_ID` | — | ключ доступа |
| `RSOCKET_S3_SECRET_ACCESS_KEY` | — | секрет |
| `RSOCKET_S3_REGION` | `us-east-1` | регион подписи; для MinIO подойдёт любой |
| `RSOCKET_S3_RULES_PREFIX` | `rules` | префикс ключей правил в бакете |
| `RSOCKET_S3_OUTPUT_PREFIX` | `output` | префикс ключей результата |

Флаги `--host` и `--port` перекрывают переменные окружения.

---

## Ручки

### `GET /`

Сводка о сервисе: доступные ручки, профиль по умолчанию, выбранное хранилище.

```
curl http://127.0.0.1:9292/
```

```json
{
  "service": "rsocket",
  "contract": "space_payments",
  "rules": "s3://rsocket/rules",
  "output": "s3://rsocket/output",
  "classifiers": ["rules"],
  "endpoints": ["GET /", "GET /health", "GET /openapi.yaml", "GET /contracts",
                "GET /rules", "POST /build", "GET /rules/<ключ>", "PUT /rules/<ключ>"],
  "openapi": "GET /openapi.yaml"
}
```

Поля `rules` и `output` содержат адреса выбранного хранилища — диска или бакета.
`classifiers` перечисляет доступные этому серверу способы распределения ролей: `rules`
присутствует всегда, остальные — только если их файлы размещены рядом с сервером.

---

### `GET /health`

Состояние сервиса и список видимых профилей. Ручку вызывает healthcheck в
`compose.yaml`.

```
curl http://127.0.0.1:9292/health
```

```json
{
  "status": "ok",
  "rules": "s3://rsocket/rules",
  "contracts": ["plain_client", "space_payments"]
}
```

Возвращает **200**, пока процесс работает.

---

### `GET /openapi.yaml`

Сервис отдаёт собственное описание в том же формате, который разбирает. Файл можно
открыть в Swagger UI или передать кодогенератору:

```
curl http://127.0.0.1:9292/openapi.yaml > rsocket.yaml
```

---

### `GET /contracts`

Профили контрактов: доступные интерфейсы, выходные файлы и роли, которые профиль ищет в
описании провайдера. Машиночитаемый аналог вывода `bin/rsocket doctor`.

```
curl http://127.0.0.1:9292/contracts
```

```json
{
  "contracts": [
    {
      "name": "space_payments",
      "title": "контракт Space Payments (Provider::BaseService)",
      "default": true,
      "files": ["contract.yml", "fixtures.json.erb", "integration.md.erb", "probe.rb",
                "service.rb.erb"],
      "outputs": ["<provider>_service.rb", "INTEGRATION.md", "fixtures.json"],
      "roles": [
        {
          "name": "create_request",
          "title": "создание выплаты",
          "threshold": 13,
          "required": true,
          "traits": ["calls_provider", "creates_operation"]
        }
      ]
    }
  ]
}
```

| Поле роли | Что означает |
|---|---|
| `name` | имя роли, оно же имя метода в сгенерированном классе |
| `threshold` | минимальный счёт: кандидат с меньшим счётом роль не занимает |
| `required` | отсутствие роли прерывает сборку вместо печати заглушки |
| `traits` | что роль значит для сборки: `calls_provider`, `creates_operation`, `receives_callback` |

Списки различаются: `files` — файлы профиля в хранилище правил, доступные для чтения и
записи; `outputs` — файлы, печатаемые на одну сборку.

---

## Менеджер правил

Что за файлы лежат в хранилище и как они устроены — [rules.md](rules.md).

Правила распознавания и шаблоны интерфейсов размещены в том же хранилище и изменяются
через API. Изменения действуют немедленно: правила читаются на каждую сборку.

### `GET /rules`

Список файлов в хранилище. Параметр `prefix` ограничивает выдачу.

```
curl "http://127.0.0.1:9292/rules?prefix=contracts/space_payments/"
```

```json
{
  "location": "s3://rsocket/rules",
  "files": [
    { "key": "contracts/space_payments/contract.yml", "kind": "rules" },
    { "key": "contracts/space_payments/service.rb.erb", "kind": "template" }
  ]
}
```

### `GET /rules/{key}`

Содержимое файла. Ключ — путь внутри хранилища: `base.yml`,
`contracts/<профиль>/contract.yml`, `contracts/<профиль>/<шаблон>.erb`.

```
curl http://127.0.0.1:9292/rules/base.yml | jq -r .content
```

### `PUT /rules/{key}`

Записать правила или шаблон. Содержимое передаётся двумя способами:

```
# телом запроса — когда правила пишут руками или отправляют готовым файлом
curl -X PUT --data-binary @contract.yml \
     "http://127.0.0.1:9292/rules/contracts/space_payments/contract.yml"

# файлом из формы
curl -X PUT -F file=@service.rb.erb \
     "http://127.0.0.1:9292/rules/contracts/space_payments/service.rb.erb"
```

```json
{ "saved": { "key": "contracts/space_payments/contract.yml", "kind": "rules", "bytes": 7199 } }
```

YAML разбирается при записи: файл с синтаксической ошибкой не сохраняется, ошибка
возвращается в ответе. Без этой проверки ошибка проявилась бы при следующей сборке.

Новый профиль контракта создаётся записью его файлов; отдельной команды нет:

```
for f in contract.yml service.rb.erb integration.md.erb fixtures.json.erb; do
  curl -X PUT --data-binary @"my_contract/$f" \
       "http://127.0.0.1:9292/rules/contracts/my_contract/$f"
done
curl -s http://127.0.0.1:9292/health | jq .contracts   # профиль уже виден
```

Ключ проверяется: выход за пределы хранилища (`../`) и недопустимые имена файлов
отклоняются.

---

## Сборка

### `POST /build`

Основная ручка: описание провайдера на входе, готовые файлы на выходе.

**Запрос**

| Где | Что | Обязателен |
|---|---|---|
| строка запроса | `provider` — имя провайдера, например `novapay` | да |
| строка запроса | `contract` — профиль контракта | нет, по умолчанию `space_payments` |
| строка запроса | `classifier` — способ распределения ролей; доступные значения перечисляет `GET /` | нет, по умолчанию `rules` |
| строка запроса | `test=1` — проверить собранный класс на его фикстурах | нет, по умолчанию не проверяется |
| тело | описание OpenAPI: YAML или JSON | да |

Тело читается как есть, `Content-Type` не учитывается: формат определяется по первому
символу (`{` — JSON, иначе YAML). Ограничение размера — 8 МБ.

Имя провайдера определяет имена результата: `novapay` → класс `NovapayService`, файл
`novapay_service.rb`, переменные окружения `NOVAPAY_*`.

```
curl -X POST "http://127.0.0.1:9292/build?provider=novapay&contract=space_payments" \
     --data-binary @examples/novapay/provider_api.yaml
```

**Ответ 200**

```json
{
  "provider": "novapay",
  "contract": "space_payments",
  "warnings": [
    "сумма провайдера: amount (integer), единицы: копейки",
    "подпись приходит в заголовке X-NovaPay-Signature"
  ],
  "locations": [
    "s3://rsocket/output/novapay/novapay_service.rb",
    "s3://rsocket/output/novapay/INTEGRATION.md",
    "s3://rsocket/output/novapay/fixtures.json",
    "s3://rsocket/output/novapay/mapping.yml"
  ],
  "files": {
    "novapay_service.rb": "# frozen_string_literal: true\n\nclass Provider\n  class NovapayService...",
    "INTEGRATION.md": "# Novapay — инструкция по подключению\n\n...",
    "fixtures.json": "{\n  \"create_request\": {\n ..."
  },
  "report": {
    "provider": "novapay",
    "contract": "space_payments",
    "api": "NovaPay Payout API 1.0.0",
    "base_url": "https://api.sandbox.novapay.example/v1",
    "roles": {
      "create_request": {
        "status": "запрос к провайдеру",
        "operation": "create_payout",
        "endpoint": "POST /payouts",
        "score": 22,
        "threshold": 13,
        "matched_rules": ["method_name =~ /(payout|disburse|withdraw|...)/", "..."]
      }
    },
    "statuses": { "completed": "approved", "failed": "rejected" },
    "conditions": [
      { "code": "amount_too_low", "kind": "min_amount", "checks": "operation.amount",
        "value": 1000, "source": "minimum у поля amount в схеме запроса" }
    ],
    "warnings": ["..."]
  }
}
```

| Поле ответа | Что в нём |
|---|---|
| `provider`, `contract` | имя провайдера и профиль контракта |
| `warnings` | решения, принятые с неполными данными, и неподдержанные конструкции |
| `locations` | размещение результата: пути в `output/` или адреса объектов в бакете |
| `files` | имя файла → содержимое строкой; набор задаёт профиль контракта, отчёт добавляется всегда |
| `report` | содержимое `mapping.yml`: роли, счёт, сработавшие правила, статусы, ограничения |
| `checks` | итог проверки собранного класса; присутствует только при `test=1` |

**Проверка собранного класса (`test=1`)**

После печати файлов собранный класс загружается и вызывается. Рядом поднимается подставной
провайдер на локальном порту, отвечающий примерами из описания — теми же, что уходят в
`fixtures.json`. Каждая роль вызывается на успешном ответе и на каждом описанном отказе.
Проверяются адрес и глагол запроса, ключ авторизации, поля тела, прочитанный
идентификатор, перевод состояния и разбор кода ошибки.

По умолчанию проверка выключена: она исполняет сгенерированный код и поднимает локальный
сервер. Результат проверки не влияет на сборку — файлы к этому моменту напечатаны.

```
curl -X POST "http://127.0.0.1:9292/build?provider=novapay&test=1" \
     --data-binary @examples/novapay/provider_api.yaml
```

```json
{
  "checks": {
    "passed": 28,
    "failed": 1,
    "notes": [],
    "checks": [
      { "role": "create_request", "check": "запрос уходит на POST /payouts", "ok": true },
      { "role": "fetch_status", "check": "запрос подписан: ApiKeyAuth", "ok": false,
        "detail": "ключа нет ни в заголовках, ни в адресе" }
    ]
  }
}
```

| Поле | Что в нём |
|---|---|
| `passed`, `failed` | количество пройденных и непройденных проверок |
| `notes` | причины, по которым проверка не выполнена: например, в профиле нет `probe.rb` |
| `checks[].role` | проверяемая роль; у проверки загрузки — имя собранного класса |
| `checks[].check` | содержание проверки |
| `checks[].ok` | результат |
| `checks[].detail` | описание расхождения; у пройденной проверки поле отсутствует |

**Разложить ответ по файлам:**

```
curl -s -X POST "http://127.0.0.1:9292/build?provider=novapay" \
     --data-binary @examples/novapay/provider_api.yaml \
| ruby -rjson -e 'JSON.parse($stdin.read)["files"].each { |name, body|
    File.write(name, body); puts name }'
```

**Взять только один файл** (при установленном `jq`):

```
curl -s -X POST "http://127.0.0.1:9292/build?provider=novapay" \
     --data-binary @examples/novapay/provider_api.yaml \
| jq -r '.files["novapay_service.rb"]' > novapay_service.rb
```

**Вывести решения, требующие проверки:**

```
curl -s -X POST "http://127.0.0.1:9292/build?provider=novapay" \
     --data-binary @examples/novapay/provider_api.yaml | jq '.warnings'
```

---

## Ошибки

Ответ об ошибке всегда JSON с полем `error`.

| Код | Когда | Пример ответа |
|---|---|---|
| `400` | не передан `provider` | `{"error": "не передан обязательный параметр provider"}` |
| `400` | пустое тело | `{"error": "описание API пустое: тело запроса"}` |
| `400` | тело не разобралось | `{"error": "не разобрать JSON: unexpected end of input at line 1 column 11"}` |
| `400` | тело не объект | `{"error": "описание API не объект: тело запроса"}` |
| `400` | описание больше 8 МБ | `{"error": "описание API слишком велико: тело запроса"}` |
| `400` | запрошен неизвестный профиль | `{"error": "контракт не найден: missing. Известны: plain_client, space_payments"}` |
| `422` | в описании не нашлись обязательные роли | `{"error": "не распознаны обязательные роли: create_request, fetch_status. Правила распознавания — в app/config/rules/base.yml, роли — в профиле контракта"}` |
| `404` | нет такой ручки | `{"error": "нет такой ручки: GET /nope", "endpoints": [...]}` |
| `500` | всё остальное | `{"error": "<класс>: <сообщение>"}` |

Коды разделены по смыслу: **400** — некорректный запрос, **422** — запрос корректен, но
описание провайдера не пригодно для сборки. В тексте ошибки 422 перечисляются недостающие
роли и указывается расположение правил.

> Кириллица в строке запроса (`?contract=профиль`) должна быть percent-encoded: иначе
> WEBrick отклонит запрос как некорректный URI до передачи в приложение. Имён профилей
> латиницей это не касается.

---

## Особенности реализации

**Состояние не хранится.** Каждый запрос — отдельная сборка, кеширование отсутствует.
Файлы возвращаются в ответе; их размещение определяет клиент.

**Правила перечитываются на каждый запрос.** Изменение `app/config/rules/base.yml` или
профиля контракта действует немедленно, перезапуск не требуется.

**Сборка синхронная.** Разбор описания занимает миллисекунды, очереди и фоновые задачи не
используются.

**Аутентификация не реализована.** Сервис рассчитан на запуск внутри контура разработки.
Для внешнего доступа требуется обратный прокси с авторизацией.

---

## Соответствие командной строке

| Задача | CLI | HTTP |
|---|---|---|
| собрать интеграцию | `bin/rsocket build -s spec.yaml -p novapay` | `POST /build?provider=novapay` + тело |
| собрать под другой контракт | `-c plain_client` | `&contract=plain_client` |
| проверить собранный класс | включено по умолчанию, отключается `--no-test` | `&test=1` |
| получить профили и роли | `bin/rsocket doctor`, `bin/rsocket contracts` | `GET /contracts` |
| прочитать правила | файлы в `app/config/rules/` | `GET /rules`, `GET /rules/<ключ>` |
| изменить правила | правка файлов в репозитории | `PUT /rules/<ключ>` |
| перенести правила в S3 | `bin/rsocket push` | — |
| проверить состояние сервиса | — | `GET /health` |

Оба способа используют один менеджер сборок. Различаются источник описания (файл или тело
запроса), расположение правил (диск или бакет) и место результата (`output/` или бакет).
