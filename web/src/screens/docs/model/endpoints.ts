export interface Endpoint {
  id: string;
  method: "GET" | "POST" | "PUT";
  path: string;

  probe?: string;
  what: string;
  request?: string;
  response: string;
  errors?: [string, string][];
}

export const ENDPOINTS: Endpoint[] = [
  {
    id: "root",
    method: "GET",
    path: "/",
    probe: "/",
    what: "Что умеет сервис. Поля rules и output показывают выбранное хранилище — по ним сразу видно, работает сервис с диском или с бакетом.",
    response: `{
  "service": "rsocket",
  "contract": "space_payments",
  "rules": "s3://rsocket/rules",
  "output": "s3://rsocket/output",
  "endpoints": ["GET /", "GET /health", "GET /openapi.yaml", "GET /contracts",
                "GET /rules", "POST /build", "GET /rules/<ключ>", "PUT /rules/<ключ>"],
  "openapi": "GET /openapi.yaml"
}`
  },
  {
    id: "health",
    method: "GET",
    path: "/health",
    probe: "/health",
    what: "Жив ли сервис и какие профили ему видны. Эту ручку дёргает healthcheck в compose.yaml. Отвечает 200, пока процесс жив.",
    response: `{
  "status": "ok",
  "rules": "s3://rsocket/rules",
  "contracts": ["plain_client", "space_payments"]
}`
  },
  {
    id: "openapi",
    method: "GET",
    path: "/openapi.yaml",
    what: "Сервис отдаёт собственное описание — в том же формате, который сам и разбирает. Его можно открыть в Swagger UI или скормить кодогенератору.",
    request: "curl http://127.0.0.1:9292/openapi.yaml > rsocket.yaml",
    response: `openapi: 3.0.3

info:
  title: rsocket — генератор интеграций с платёжными провайдерами
  version: "1.0.0"
  description: |
    Инструмент читает описание API платёжного провайдера в формате OpenAPI и
    собирает по нему заготовку интеграции: класс на Ruby под контракт заказчика,
    инструкцию по подключению, тестовые фикстуры и отчёт о разборе.
…`
  },
  {
    id: "contracts",
    method: "GET",
    path: "/contracts",
    probe: "/contracts",
    what: "Профили контрактов: подо что можно собирать, какие файлы получатся и какие роли профиль ищет в описании. files — из чего профиль состоит в хранилище, outputs — что он печатает на одну сборку.",
    response: `{
  "contracts": [
    {
      "name": "space_payments",
      "title": "контракт Space Payments (Provider::BaseService)",
      "default": true,
      "files": ["contract.yml", "fixtures.json.erb", "integration.md.erb", "service.rb.erb"],
      "outputs": ["<provider>_service.rb", "INTEGRATION.md", "fixtures.json"],
      "roles": [
        { "name": "create_request", "title": "создание выплаты", "threshold": 10,
          "required": true, "traits": ["calls_provider", "creates_operation"] }
      ]
    }
  ]
}`
  },
  {
    id: "rules",
    method: "GET",
    path: "/rules",
    probe: "/rules",
    what: "Что лежит в хранилище правил. Параметр prefix сужает выдачу — например contracts/space_payments/.",
    request: 'curl "http://127.0.0.1:9292/rules?prefix=contracts/space_payments/"',
    response: `{
  "location": "s3://rsocket/rules",
  "files": [
    { "key": "contracts/space_payments/contract.yml", "kind": "rules" },
    { "key": "contracts/space_payments/fixtures.json.erb", "kind": "template" },
    { "key": "contracts/space_payments/integration.md.erb", "kind": "template" },
    { "key": "contracts/space_payments/service.rb.erb", "kind": "template" }
  ]
}`
  },
  {
    id: "rule-read",
    method: "GET",
    path: "/rules/{key}",
    probe: "/rules/base.yml",
    what: "Содержимое файла правил. Ключ — путь внутри хранилища: base.yml, contracts/<профиль>/contract.yml, contracts/<профиль>/<шаблон>.erb.",
    request: "curl http://127.0.0.1:9292/rules/base.yml | jq -r .content",
    response: `{
  "key": "base.yml",
  "content": "# Распознавание чужого API: как разные провайдеры называют одни и\\n# те же операции, поля и заголовки. От контракта заказчика здесь\\n# не зависит ничего…"
}`,
    errors: [["404", "нет такого ключа в хранилище"]]
  },
  {
    id: "rule-write",
    method: "PUT",
    path: "/rules/{key}",
    what: "Записать правила или шаблон. Содержимое передаётся телом запроса или файлом из формы. YAML проверяется на разбор сразу: испорченные правила не запишутся — иначе они свалили бы не запись, а следующую сборку. Ключи проверяются: выйти за пределы хранилища (../) нельзя.",
    request: `curl -X PUT --data-binary @contract.yml \\
     "http://127.0.0.1:9292/rules/contracts/space_payments/contract.yml"`,
    response: `{ "saved": { "key": "contracts/space_payments/contract.yml",
            "kind": "rules", "bytes": 7199 } }`,
    errors: [
      ["400", "YAML не разобрался или ключ выходит за пределы хранилища"],
      ["413", "содержимое слишком велико"]
    ]
  },
  {
    id: "build",
    method: "POST",
    path: "/build",
    what: "Главная ручка: описание провайдера → готовые файлы. Тело читается как есть, Content-Type не важен: формат определяется по первому символу ({ — JSON, иначе YAML). Ограничение — 8 МБ. Имя провайдера участвует в именах: novapay → класс NovapayService, файл novapay_service.rb, переменные NOVAPAY_*.",
    request: `curl -X POST "http://127.0.0.1:9292/build?provider=novapay&contract=space_payments" \\
     --data-binary @examples/novapay/provider_api.yaml`,
    response: `{
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
  "files": { "novapay_service.rb": "# frozen_string_literal: true\\n\\nclass Provider…" },
  "report": {
    "roles": {
      "create_request": {
        "status": "запрос к провайдеру", "operation": "create_payout",
        "endpoint": "POST /payouts", "score": 15, "threshold": 10,
        "matched_rules": ["operation_id =~ /\\\\A(create|make|submit|…)/"]
      }
    },
    "statuses": { "completed": "approved", "failed": "rejected" },
    "amount": { "multiplier": 100, "note": "сумма уходит в копейках" }
  }
}`,
    errors: [
      ["400", "не передан provider, пустое тело, тело не разобралось, не объект, больше 8 МБ, неизвестный профиль"],
      ["422", "в описании не нашлись обязательные роли — текст называет, каких не хватило"],
      ["500", "всё остальное: <класс>: <сообщение>"]
    ]
  }
];

export const NOT_FOUND = `{
  "error": "нет такой ручки: GET /nope",
  "endpoints": ["GET /", "GET /health", "GET /openapi.yaml", "GET /contracts",
                "GET /rules", "POST /build", "GET /rules/<ключ>", "PUT /rules/<ключ>"]
}`;
