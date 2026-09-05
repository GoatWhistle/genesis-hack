# HTTP API

Тот же инструмент, что и в командной строке, только по HTTP. Сервер ничего не решает сам:
он разбирает запрос, зовёт тот же менеджер сборок и печатает результат JSON-ом. Поэтому
`bin/rsocket build` и `POST /build` на одном и том же описании дают одинаковые файлы.

Машиночитаемое описание этого API — [docs/openapi.yaml](openapi.yaml); сервис отдаёт его
и сам, ручкой `GET /openapi.yaml`.

Команды:

| Команда | Что делает |
|---|---|
| `bin/rsocket build` | одна сборка: правила с диска, файлы в `output/` |
| `bin/rsocket serve` | HTTP-сервер: правила и результат в S3 |
| `bin/rsocket push` | переносит локальные правила и шаблоны в S3 |
| `bin/rsocket contracts`, `doctor` | что за профили есть и по каким правилам разбирают |

## Хранилища

Правила (`base.yml`, профили контрактов и их шаблоны) и результат сборки лежат в
хранилище, которое выбирается **при запуске**:

| | Правила | Результат |
|---|---|---|
| `local` | каталог `app/config/rules/` | каталог `output/<provider>/` |
| `s3` | `s3://<бакет>/rules/` | `s3://<бакет>/output/<provider>/` |

Командная строка работает локально, сервер — через S3. Это умолчания, и оба
перекрываются флагом `--storage` или переменной `RSOCKET_STORAGE`.

**S3 можно не использовать вовсе.** С `RSOCKET_STORAGE=local` сервер работает с диском, и
для запуска не нужно ничего, кроме репозитория. Если же S3 выбран, но не настроен, сервис
не поднимется и скажет, каких переменных не хватает — вместо того чтобы упасть на первом
запросе.

Правила читаются на каждый запрос, поэтому правка действует немедленно: и когда файл
поправили на диске, и когда его записали через `PUT /rules/<ключ>`.

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
  POST /build        — сборка: ?provider=имя[&contract=профиль], тело — описание
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

Без `--storage local` серверу нужен настроенный S3 — см. таблицу переменных ниже.

По умолчанию сервер слушает только localhost. Это осознанно: инструмент выполняет разбор
чужих описаний и не имеет ни аутентификации, ни ограничения частоты запросов, поэтому
выставлять его наружу без прикрытия не нужно.

### Через rackup

`config.ru` лежит в корне, так что подойдёт любой сервер приложений:

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

Стек поднимает три вещи: MinIO как S3-хранилище, разовый шаг `rules` (он переносит
локальные правила в бакет командой `bin/rsocket push`) и сам сервер. Консоль MinIO —
на `localhost:9001`, логин и пароль `rsocket` / `rsocket-secret`.

Разовая сборка тем же образом, без поднятия сервера:

```
docker compose run --rm rsocket \
  bundle exec bin/rsocket build -s examples/novapay/provider_api.yaml -p novapay -o output
```

Каталог `output/` и каталог правил `app/config/rules/` смонтированы с хоста — правки видны
контейнеру сразу. При работе через S3 правила берутся из бакета, а туда они попадают
командой `push`; поменять их можно и на месте — ручкой `PUT /rules/<ключ>`.

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

Что умеет сервис. Полезно как первая проверка после запуска.

```
curl http://127.0.0.1:9292/
```

```json
{
  "service": "rsocket",
  "contract": "space_payments",
  "rules": "s3://rsocket/rules",
  "output": "s3://rsocket/output",
  "endpoints": ["GET /", "GET /health", "GET /openapi.yaml", "GET /contracts",
                "GET /rules", "POST /build", "GET /rules/<ключ>", "PUT /rules/<ключ>"],
  "openapi": "GET /openapi.yaml"
}
```

Поля `rules` и `output` показывают выбранное хранилище — по ним сразу видно, работает
сервис с диском или с бакетом.

---

### `GET /health`

Жив ли сервис и какие профили ему видны. Эту ручку дёргает healthcheck в `compose.yaml`.

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

**200** — всегда, если процесс жив.

---

### `GET /openapi.yaml`

Сервис отдаёт собственное описание — в том же формате, который сам и разбирает. Его можно
открыть в Swagger UI или скормить кодогенератору:

```
curl http://127.0.0.1:9292/openapi.yaml > rsocket.yaml
```

---

### `GET /contracts`

Профили контрактов: под какой интерфейс можно собирать, какие файлы получатся и какие
роли профиль ищет в описании провайдера. То же, что печатает `bin/rsocket doctor`, только
машиночитаемо.

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
      "files": ["contract.yml", "fixtures.json.erb", "integration.md.erb", "service.rb.erb"],
      "outputs": ["<provider>_service.rb", "INTEGRATION.md", "fixtures.json"],
      "roles": [
        {
          "name": "create_request",
          "title": "создание выплаты",
          "threshold": 10,
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
| `threshold` | минимальный счёт: кандидат ниже порога роль не занимает |
| `required` | без этой роли сборка остановится, а не напечатает заглушку |
| `traits` | что роль значит для сборки: `calls_provider`, `creates_operation`, `receives_callback` |

Здесь два разных списка: `files` — из чего профиль состоит в хранилище правил (его можно
читать и править), `outputs` — что он печатает на одну сборку.

---

## Менеджер правил

Правила распознавания и шаблоны интерфейсов лежат в том же хранилище и правятся прямо
через API. Изменения действуют немедленно: правила читаются на каждую сборку.

### `GET /rules`

Что лежит в хранилище. Параметр `prefix` сужает выдачу.

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

YAML проверяется на разбор сразу: испорченные правила не запишутся — иначе они свалили бы
не запись, а следующую сборку, и разбираться пришлось бы уже другому человеку.

**Новый профиль контракта** создаётся простой записью его файлов — отдельной команды нет:

```
for f in contract.yml service.rb.erb integration.md.erb fixtures.json.erb; do
  curl -X PUT --data-binary @"my_contract/$f" \
       "http://127.0.0.1:9292/rules/contracts/my_contract/$f"
done
curl -s http://127.0.0.1:9292/health | jq .contracts   # профиль уже виден
```

Ключи проверяются: выйти за пределы хранилища (`../`) или записать файл со странным
именем нельзя.

---

## Сборка

### `POST /build`

Главная ручка: описание провайдера → готовые файлы.

**Запрос**

| Где | Что | Обязателен |
|---|---|---|
| строка запроса | `provider` — имя провайдера, например `novapay` | да |
| строка запроса | `contract` — профиль контракта | нет, по умолчанию `space_payments` |
| тело | описание OpenAPI: YAML или JSON | да |

Тело читается как есть, `Content-Type` не важен: формат определяется по первому символу
(`{` — JSON, иначе YAML). Ограничение на размер — 8 МБ.

Имя провайдера участвует в именах: `novapay` → класс `NovapayService`, файл
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
        "score": 15,
        "threshold": 10,
        "matched_rules": ["operation_id =~ /\\A(create|make|submit|...)/", "..."]
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
| `provider`, `contract` | что и подо что собрано |
| `warnings` | всё, в чём инструмент не уверен, и решения, которые стоит проверить глазами |
| `locations` | куда результат сложен: пути в `output/` или адреса объектов в бакете |
| `files` | имя файла → его содержимое строкой. Набор задаёт профиль контракта, отчёт добавляется всегда |
| `report` | тот же разбор, что уходит в `mapping.yml`: роли, счёт, сработавшие правила, статусы, ограничения |

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

**Посмотреть, что инструмент не понял:**

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

Разница между 400 и 422 намеренная: **400** — запрос сформулирован неверно, **422** — запрос
понят, но описание провайдера не годится для сборки. Во втором случае текст ошибки называет
роли, которых не хватило, и говорит, где лежат правила.

> Кириллица в строке запроса (`?contract=профиль`) должна быть percent-encoded — иначе
> WEBrick отклонит запрос как некорректный URI ещё до нашего кода. Имена профилей латиницей
> этой проблемы не имеют.

---

## Что важно знать

**Сервер не хранит состояние.** Каждый запрос — отдельная сборка: ничего не кешируется,
на диск ничего не пишется. Файлы отдаются в ответе, а куда их положить, решает клиент.

**Правила перечитываются на каждый запрос.** Правка `app/config/rules/base.yml` или профиля
контракта действует немедленно, перезапуск не нужен. Удобно на демонстрации: поменяли
регулярку — повторили запрос — увидели другое распределение ролей.

**Сборка синхронная.** Разбор описания занимает миллисекунды даже на больших файлах, поэтому
очередей и фоновых задач здесь нет.

**Аутентификации нет.** Инструмент рассчитан на запуск внутри контура разработки. Если он
нужен снаружи, ставьте перед ним обратный прокси с авторизацией.

---

## Соответствие командной строке

| Задача | CLI | HTTP |
|---|---|---|
| собрать интеграцию | `bin/rsocket build -s spec.yaml -p novapay` | `POST /build?provider=novapay` + тело |
| собрать под другой контракт | `-c plain_client` | `&contract=plain_client` |
| посмотреть профили и роли | `bin/rsocket doctor`, `bin/rsocket contracts` | `GET /contracts` |
| посмотреть правила | открыть `app/config/rules/` | `GET /rules`, `GET /rules/<ключ>` |
| поправить правила | править файлы в репозитории | `PUT /rules/<ключ>` |
| перенести правила в S3 | `bin/rsocket push` | — |
| проверить, что инструмент жив | — | `GET /health` |

Оба пути ведут в один и тот же менеджер сборок. Отличается только то, откуда приходит
описание (файл или тело запроса), где лежат правила (диск или бакет) и куда уходит
результат (`output/` или бакет).
