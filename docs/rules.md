# Правила: base.yml и contract.yml

Поведение инструмента задаётся двумя YAML-файлами. `base.yml` описывает распознавание
чужого API, `contract.yml` — интерфейс, под который собирается класс. Код инструмента при
изменении правил не меняется.

```
app/config/rules/
├── base.yml                       # распознавание чужого API, общее для всех контрактов
└── contracts/
    ├── space_payments/            # профиль контракта
    │   ├── contract.yml           #   роли, статусы, ошибки, выражения
    │   ├── probe.rb               #   вызов собранного класса при проверке
    │   ├── service.rb.erb         #   шаблоны выходных файлов
    │   ├── integration.md.erb
    │   └── fixtures.json.erb
    └── plain_client/
        └── ...
```

Разделение соблюдается строго: в `base.yml` нет имён методов контракта, в `contract.yml`
нет имён провайдеров. Поэтому новое написание `operationId` добавляется один раз и
действует для всех контрактов, а новый контракт не затрагивает распознавание.

| Изменение | Файл |
| --------- | ---- |
| распознавать операцию `submitDisbursement` | `base.yml` |
| считать состояние `AWAITING_FUNDS` незавершённым | `base.yml` |
| считать поле `payeeCardToken` токеном карты | `base.yml` |
| назвать метод контракта `create_request`, а не `send_payout` | `contract.yml` |
| отвечать на 429 кодом `rate_limit` с повтором | `contract.yml` |
| брать сумму из `operation.amount`, а не из `payment[:amount]` | `contract.yml` |

Текущее состояние правил печатает `bundle exec bin/rsocket doctor`. По HTTP правила
читаются и пишутся через `GET`/`PUT /rules/<ключ>` без перезапуска — см.
[http-api.md](http-api.md).

---

# base.yml

## archetypes

Архетип описывает признаки операции определённого назначения. Объявлено четыре:
`creation`, `status_lookup`, `callback`, `cancellation`. Роль контракта ссылается на
архетип по имени; имя роли при этом произвольно.

У архетипа два списка правил: `rules` начисляют очки, `veto` исключают кандидата.

```yaml
archetypes:
  creation:
    rules:
      - { field: method_name, pattern: '(payout|disburse|withdraw|remit|transfer)', weight: 6 }
      - { field: http_method, pattern: '\Apost\z', weight: 2 }
    veto:
      - { field: method_name, pattern: '(refund|cancel|revoke|reverse)' }
      - { field: http_method, pattern: '\A(get|delete|head)\z' }
```

Правило состоит из трёх ключей:

| Ключ | Значение |
| ---- | -------- |
| `field` | поле операции, по которому проверяется совпадение |
| `pattern` | регулярное выражение, компилируется без учёта регистра |
| `weight` | очки за совпадение; в `veto` не используется |

Допустимые значения `field` (`Config::Rule::FIELDS`); другое значение приводит к
`ArgumentError` при загрузке правил:

`method_name`, `operation_id`, `path`, `http_method`, `summary`, `description`, `tags`.

`method_name` — это `operationId` в `snake_case`; если `operationId` в описании нет, имя
собирается из глагола HTTP и пути (`post_payouts`). Правило по `method_name` применимо к
описаниям без `operationId`, правило по `operation_id` — нет. Значение поля `tags`
склеивается в строку через пробел.

Веса разделяют признаки по значимости. `POST` встречается в большинстве операций и
оценивается в 2 очка; слово, обозначающее исходящий платёж (`payout`, `disburse`,
`withdraw`), — в 6. Очки сработавших правил суммируются и сравниваются с порогом роли из
`contract.yml`.

`veto` проверяется до подсчёта очков и исключает кандидата целиком. Без него
`cancelPayout` набрал бы очки как создание выплаты: это `POST` со словом `payout` в
имени.

Правила роли добавляются к правилам архетипа, а не заменяют их: контракт может объявить
собственные `rules` и `veto`, не изменяя архетип и не влияя на другие контракты.

### Порядок разбора

Роли обрабатываются в порядке `classification.order` из `contract.yml`. Для каждой роли
кандидаты, не исключённые `veto`, получают очки; выигрывает кандидат с наибольшим счётом.
При равенстве очков выбирается операция, объявленная в описании раньше, — так результат
не зависит от порядка ключей в хеше. Если лучший счёт меньше порога роли, роль остаётся
незанятой, а в отчёт попадает строка вида «лучший кандидат X набрал N при пороге M».

Операция, занятая одной ролью, в последующих ролях не участвует. Поэтому порядок в
`order` влияет на результат: роль, объявленная раньше, выбирает первой.

## status_patterns

Значения, которыми провайдеры обозначают состояние операции, сгруппированные по смыслу.
Имена групп внутренние; контракт переводит их в свои статусы.

```yaml
status_patterns:
  settled:
    - '\A(completed?|success(ful)?|paid|delivered|executed|settled|approved)\z'
  failed:
    - '\A(failed|declined|rejected|cancell?ed|revoked|aborted|reversed|expired)\z'
  pending:
    - '\A(pending|processing|in_?progress|new|created|accepted|queued|await\w*)\z'
```

Сравнение регистронезависимое: часть провайдеров записывает состояния в верхнем регистре.
Значения берутся из `enum` в схемах ответов. Состояние, не совпавшее ни с одной группой,
попадает в `warnings` отчёта строкой «состояние «X» не перевести в статус контракта».

Новая группа применяется только после того, как контракт сошлётся на неё в секции
`statuses`.

## error_semantics

```yaml
error_semantics:
  "400": bad_request
  "401": credentials
  "402": insufficient_funds
  "409": conflict
  "429": rate_limit
  "503": unavailable
```

Секция задаёт смысл HTTP-кода. Реакцию на этот смысл определяет контракт. Связь:
код → смысл (`base.yml`) → запись контракта (`contract.yml`).

Ключ приводится к строке при загрузке, поэтому `400:` и `"400":` эквивалентны.

Каждый смысл, объявленный здесь, должен присутствовать в `errors.semantics` контракта:
секция читается по этим именам, отсутствующее имя вызывает `KeyError` при загрузке
правил. При добавлении смысла в `base.yml` его нужно добавить во все профили.

## payload_patterns, requisite_patterns, path_patterns

Словари сопоставляют свойство схемы провайдера внутреннему имени поля. Применяется первое
правило, чья регулярка совпала с именем свойства, поэтому порядок записей значим.

```yaml
payload_patterns:
  - { field: amount, patterns: ['\Aamount\z', '\Asum\z', '\Avalue\z', '\Atotal\z'] }
  - { field: external_id, patterns: ['external_?id', 'merchant_?reference', 'order_?(no|id)'] }
  - { field: recipient, patterns: ['\Arecipient\z', '\Abeneficiary\z', '\Apayee\z'] }
```

| Словарь | Область применения |
| ------- | ------------------ |
| `payload_patterns` | свойства тела запроса |
| `requisite_patterns` | свойства внутри объекта получателя |
| `path_patterns` | параметры пути и обязательные параметры строки запроса |

Разбор спускается во вложенные объекты на глубину не более трёх уровней. Словарь для
вложенного уровня выбирается так:

* объект, распознанный как `recipient`, и объект, не распознанный ни одним правилом, —
  словарь реквизитов;
* объект, распознанный как другое поле (например `sum`), — словарь тела запроса.

Вложенный объект, ни одно свойство которого не распознано, считается незаполненным
целиком.

Выражение для заполнения поля задаёт секция `sources` контракта. Поле без выражения
обрабатывается так:

* обязательное — печатается с комментарием
  `# TODO: правила не знают, чем заполнить это поле` и попадает в `warnings`;
* необязательное — не печатается.

## callback_fields

```yaml
callback_fields:
  operation_id: ['\A\w*(payout|payment|transfer|operation|order)_?id\z', '\Aid\z']
  event: ['\Aevent\w*\z', '\Atype\z', '\Aaction\z']
  status: ['\Astatus\z', '\Astate\z']
  error_code: ['\Aerror\z', 'error_?code', 'failure', '\Areason\z']
  error_detail: ['\Acode\z', '\Areason\z', '\Amessage\z']
```

Секция определяет, какие поля искать в теле webhook. `error_detail` ищется внутри объекта
ошибки и предназначен для машинного кода, а не текста сообщения. Словарь `status`
используется также при поиске поля состояния в телах ответов.

## headers

```yaml
headers:
  idempotency: ['idempotenc', 'request[-_]?id', 'correlation[-_]?id', 'x-.*-token']
  signature: ['signature', '\Asign\z', 'hmac', 'digest']
  signature_algorithms: ['HMAC-SHA-?(?<bits>\d{3})', 'SHA-?(?<bits>\d{3})']
```

`idempotency` и `signature` задают назначение заголовка независимо от его имени у
провайдера (`Idempotency-Key`, `X-Request-Id`). Выражение для заполнения задаёт
`sources.headers` контракта.

Регулярки `signature_algorithms` обязаны содержать именованную группу `bits`: из неё
формируется имя алгоритма (`sha256`). Алгоритм ищется в тексте описания операции и
заголовка — отдельного поля под него в OpenAPI нет.

## amount_units и amount_text_rules

```yaml
amount_units:
  minor_patterns: ['копейк', 'коп\.', 'kopeck', 'minor units?', '\bcents?\b']
  multiplier: 100
  minor_requires_integer: true

amount_text_rules:
  - { kind: min_amount, comparison: less_than, pattern: 'минимальн\w*\s+сумм\w*\D{0,20}(?<value>[\d\s]+)' }
  - { kind: max_amount, comparison: greater_than, pattern: 'maximum amount\D{0,20}(?<value>[\d\s]+)' }
```

`minor_patterns` проверяются по описанию поля суммы, описанию операции и описанию API.
При совпадении сумма передаётся в минорных единицах с множителем `multiplier`.

`minor_requires_integer: true` ограничивает признание минорных единиц целочисленным
полем. У строкового поля те же слова описывают формат записи («рубли и копейки через
точку»), а не единицы: без ограничения значение `1500.00` было бы умножено на 100.

`amount_text_rules` извлекают границы суммы из текста описания, когда их нет в схеме.
Регулярка обязана содержать именованную группу `value`. `kind` — внутреннее имя
ограничения (`min_amount`, `max_amount`); его представление в коде задаёт секция
`conditions` контракта. `comparison` (`less_than`, `greater_than`) задаёт сравнение, при
котором операция отклоняется.

Границы из схемы (`minimum`, `maximum`) имеют приоритет над текстом: текст используется
только для того вида ограничения, которого нет в схеме. Множитель к числу из текста не
применяется — в описании сумма указывается в основной валюте.

---

# contract.yml

Профиль задаёт один интерфейс, под который собирается класс. Количество профилей не
ограничено. Профиль по умолчанию задаёт `RSOCKET_CONTRACT`, профиль конкретной сборки —
флаг `--contract` или параметр `?contract=`.

## contract

```yaml
contract:
  title: контракт Space Payments (Provider::BaseService)
  class_suffix: Service
  probe: probe.rb
  outputs:
    - { template: service.rb.erb, file: "%<provider>s_service.rb" }
    - { template: integration.md.erb, file: INTEGRATION.md }
    - { template: fixtures.json.erb, file: fixtures.json }
```

| Ключ | Значение |
| ---- | -------- |
| `title` | название профиля для вывода `doctor` и `GET /contracts` |
| `class_suffix` | суффикс имени класса: `novapay` + `Service` → `NovapayService` |
| `probe` | файл проверки собранного класса; ключ необязателен |
| `outputs` | список выходных файлов сборки |

В `outputs` подстановка `%<provider>s` заменяется именем провайдера. Первый файл списка
считается основным: его исходник загружает проверка, он же возвращается как
`result.source`. Отчёт `mapping.yml` печатается всегда и в списке не указывается.

`probe` — исходник на Ruby, вызывающий роли этого интерфейса. Он исполняется в песочнице
рядом с собранным классом, предоставляет отсутствующие зависимости (для `space_payments` —
базовый класс контракта) и преобразует пару «роль, заявка» в вызов метода. Профиль без
`probe` не проверяется; причина указывается в `notes` отчёта.

## http

```yaml
http:
  open_timeout: 5
  read_timeout: 15
  user_agent: "space-payments-adapter/1.0"
```

Значения печатаются константами класса и применяются при следующей сборке.

## classification

```yaml
classification:
  order: [create_request, fetch_status, process_callback, cancel_request]
  required: [create_request, fetch_status]
  thresholds:
    default: 8
    create_request: 13
    fetch_status: 14
  status_sources: [fetch_status, create_request, process_callback]
  roles:
    create_request:
      title: создание выплаты
      archetype: creation
      traits: [calls_provider, creates_operation]
```

| Ключ | Значение |
| ---- | -------- |
| `order` | порядок разбора ролей |
| `required` | роли, отсутствие которых прерывает сборку |
| `thresholds` | минимальный счёт по роли; `default` применяется к остальным |
| `status_sources` | роли, по ответам которых определяются состояния, в порядке приоритета |
| `roles` | описания ролей |

Имя роли используется как имя метода собранного класса: `create_request` в конфигурации
соответствует `def create_request` в коде. Печатает метод шаблон профиля, поэтому имена
ролей и имена методов в шаблоне изменяются согласованно.

Порог отсекает кандидатов со слабым набором признаков. Для `create_request` он равен 13,
так как операция без слова об исходящем платеже набирает 12 очков: глагол создания (6),
слабое существительное (2), `POST` (2), путь без параметров (2). Для `fetch_status` он
равен 14 по той же причине: `GET` по идентификатору присутствует в большинстве описаний.
Значения подбираются по счёту из `mapping.yml`.

`status_sources` задаёт приоритет источников состояний: перечисление в ответе
статус-запроса обычно полнее, ответ на создание используется как запасной источник.

### Роль

| Ключ | Обязателен | Значение |
| ---- | ---------- | -------- |
| `title` | да | название роли для отчёта, предупреждений и комментариев в коде |
| `archetype` | да | архетип `base.yml`, по которому роль распознаётся |
| `traits` | да | назначение роли для сборки |
| `rules`, `veto` | нет | дополнительные правила в формате архетипа |

Признаки (`traits`) позволяют сборке находить нужную роль независимо от её имени:

| Признак | Значение |
| ------- | -------- |
| `calls_provider` | для роли планируется запрос к провайдеру; она участвует в проверке |
| `creates_operation` | роль-источник тела запроса, ограничений, авторизации и идентификатора операции |
| `receives_callback` | тело операции описывает входящий webhook, а не запрос к провайдеру |

Признак `creates_operation` должна нести ровно одна роль, `receives_callback` — не более
одной. Нарушение приводит к `ArgumentError` при загрузке правил: на этих ролях основан
последующий разбор.

## statuses

```yaml
statuses:
  approved: settled
  rejected: failed
  in_progress: pending
```

Ключ — статус контракта, значение — имя группы из `status_patterns`. Вместо ссылки на
группу контракт может задать собственные шаблоны списком:

```yaml
statuses:
  paid: ['\A(paid|settled)\z']
```

## errors

```yaml
errors:
  default: { code: unknown_error, action: alert, symbol: bad_gateway }
  semantics:
    validation:  { code: validation_error,  action: reject,        symbol: unprocessable_entity }
    rate_limit:  { code: rate_limit,        action: retry_backoff, symbol: too_many_requests }
    unavailable: { code: provider_unavailable, action: retry,      symbol: service_unavailable }
```

Ключи `semantics` — смыслы из `error_semantics` базы. Значение — запись контракта:

| Ключ | Значение |
| ---- | -------- |
| `code` | код ошибки в терминах контракта |
| `action` | реакция; значения с префиксом `retry` считаются допускающими повтор |
| `symbol` | символ HTTP-статуса, если контракт его использует |

Состав записи определяет контракт: `plain_client` поднимает исключение и ключ `symbol` не
объявляет. `default` применяется к кодам, отсутствующим в словаре.

## sources

Секция задаёт выражения на Ruby, которыми заполняются распознанные поля. Имя поля берётся
из словарей `base.yml`, выражение печатается в собранном классе как есть.

```yaml
sources:
  payload:
    amount: 'provider_amount(operation)'
    currency: 'operation.currency'
    external_id: 'operation.id'
  requisite:
    phone: 'requisite(operation, "phone")'
    card_number: 'requisite(operation, "card_number")'
  path:
    provider_id: 'operation.provider_operation_id'
  headers:
    idempotency: 'operation.id'
```

| Раздел | Источник ключей |
| ------ | --------------- |
| `payload` | `field` из `payload_patterns` |
| `requisite` | `field` из `requisite_patterns` |
| `path` | `field` из `path_patterns` |
| `headers` | назначения заголовков из `headers` |

Поле, для которого выражение не задано, считается незаполненным — см. раздел о словарях.
Выражения зависят от интерфейса: в `plain_client` вместо `operation.currency`
используется `payment[:currency]`.

## amount

```yaml
amount:
  integer_minor: '(operation.amount * 100).to_i'
  integer_major: 'operation.amount.to_i'
  decimal_string: 'format("%.2f", operation.amount)'
  string: 'operation.amount.to_s'
  number: 'operation.amount.to_f'
```

Вариант выбирается по схеме поля суммы:

| Схема поля суммы | Выбранный ключ |
| ---------------- | -------------- |
| `integer`, в описании найдены минорные единицы | `integer_minor` |
| `integer` | `integer_major` |
| `string` с точкой в `pattern` | `decimal_string` |
| `string` | `string` |
| прочее или поле суммы не найдено | `number` |

Объявлять нужно все пять ключей: значение читается через `fetch`.

## conditions

```yaml
conditions:
  min_amount: { code: amount_too_low,       constant: MIN_AMOUNT,          subject: 'operation.amount' }
  max_amount: { code: amount_too_high,      constant: MAX_AMOUNT,          subject: 'operation.amount' }
  currency:   { code: unsupported_currency, constant: ALLOWED_CURRENCIES,  subject: 'operation.currency' }
```

Ключ — внутренний вид ограничения. `min_amount` и `max_amount` совпадают с именами из
`amount_text_rules`; граница берётся из `minimum`/`maximum` схемы или из текста описания.
`currency` формируется, когда у поля валюты в схеме объявлен `enum`; список допустимых
значений берётся оттуда.

| Ключ | Значение |
| ---- | -------- |
| `code` | код отказа контракта |
| `constant` | имя константы, в которую печатается найденная граница |
| `subject` | выражение, сравниваемое с границей |

Ограничение, отсутствующее в секции, не проверяется. Секция может быть пустой; что
печатается при отсутствии проверок, определяет шаблон: в `space_payments` метод сводится
к вызову `super`, в `plain_client` `check!` возвращает `true`.

## authorization

```yaml
authorization:
  api_key_header: 'message["%<parameter>s"] = credential(:api_key)'
  api_key_query:  '# Ключ уходит в строке запроса — см. build_uri.'
  query_pair:     '{ "%<parameter>s" => credential(:api_key) }'
  bearer:         'message["Authorization"] = "Bearer #{credential(:access_token)}"'
  basic:          'message.basic_auth(credential(:username).to_s, credential(:password).to_s)'
  unsupported:    '# TODO: схема %<name>s не поддержана — подпишите запрос здесь'
  missing:        '# TODO: в описании нет securitySchemes — подпишите запрос здесь'
  comment:        'Авторизация: %<name>s (%<kind>s).'
  comment_missing: 'В описании провайдера нет securitySchemes.'
```

Заготовки строк, печатаемых в метод `authorize`. Доступные подстановки:

| Подстановка | Значение |
| ----------- | -------- |
| `%<parameter>s` | имя заголовка или параметра из описания провайдера |
| `%<name>s` | имя схемы авторизации из описания |
| `%<kind>s` | распознанный вид схемы: `api_key`, `bearer`, `basic` |

Заготовка выбирается по описанию провайдера: `apiKey` в заголовке → `api_key_header`,
`apiKey` в строке запроса → `api_key_query` и `query_pair`, `http` со схемой `bearer` →
`bearer`. При нескольких объявленных схемах выбирается указанная первой у операции
создания; остальные попадают в отчёт как альтернативы.

---

# Типовые изменения

## Новое написание операции

Провайдер называет создание выплаты `initiateSettlementOut`; слова `settlement` в
правилах нет. Оно добавляется в правило, перечисляющее слова об исходящем платеже:

```yaml
archetypes:
  creation:
    rules:
      - { field: method_name, pattern: '(payout|disburse|withdraw|remit|transfer|settlement)', weight: 6 }
```

Изменение действует для всех контрактов. Результат проверяется сборкой на описании с этим
словом: в `mapping.yml` видно счёт роли и список сработавших правил.

## Новый профиль контракта

1. Создать `app/config/rules/contracts/<имя>/contract.yml`.
2. Положить рядом шаблоны, перечисленные в `outputs`.
3. Положить рядом `probe.rb`, если сборка должна проверяться.

Код инструмента при этом не изменяется. `bin/rsocket contracts` покажет новый профиль,
`--contract <имя>` соберёт под него.

## Проверка после изменений

```
bundle exec bin/rsocket doctor --contract <имя>   # роли, пороги, количество правил
bundle exec bin/rsocket build -s ... -p ...       # сборка с проверкой собранного класса
```

Результат разбора — в `mapping.yml`: счёт и порог по каждой роли, сработавшие правила,
предупреждения и итог проверки собранного класса.
