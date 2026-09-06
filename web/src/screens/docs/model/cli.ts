import type { Take } from "~/shared/ui/Terminal";

export type { Take };

export const TAKES: Take[] = [
  {
    id: "build",
    command: "bin/rsocket build -s examples/nordbank/provider_api.yaml -p nordbank -o output",
    about:
      "Одна сборка: правила берутся с диска, файлы ложатся в output/. Nordbank взят нарочно — из четырёх описаний он даёт больше всего замечаний, пять.",
    lines: [
      "контракт: space_payments",
      "  create_request     POST /payment-orders",
      "  fetch_status       GET /payment-orders/{paymentId}",
      "  process_callback   заглушка",
      "  cancel_request     POST /payment-orders/{paymentId}/revocation",
      "  ! обработка webhook: лучший кандидат revoke_payment_order набрал 1 при пороге 8",
      "  ! поле beneficiary заполняется одним из 2 способов — взят первый, проверьте его",
      "  ! сумма провайдера: amount (string), единицы: рубли",
      "  ! провайдер не описывает webhook — статус узнаётся опросом",
      "  ! в описании нет securitySchemes — авторизацию придётся дописать руками",
      "",
      "  output/nordbank/nordbank_service.rb",
      "  output/nordbank/INTEGRATION.md",
      "  output/nordbank/fixtures.json",
      "  output/nordbank/mapping.yml"
    ]
  },
  {
    id: "doctor",
    command: "bin/rsocket doctor",
    about:
      "По каким правилам разбирают описание: роли контракта, их пороги и сколько правил у каждой. Ни одного имени провайдера здесь нет — знание живёт в YAML.",
    lines: [
      "контракт: space_payments — контракт Space Payments (Provider::BaseService)",
      "правила:  локальный каталог /app/app/config/rules",
      "  create_request     порог 10, обязательна,    правил: 5, calls_provider creates_operation",
      "  fetch_status       порог  8, обязательна,    правил: 4, calls_provider",
      "  process_callback   порог  8, необязательна,  правил: 4, receives_callback",
      "  cancel_request     порог  8, необязательна,  правил: 4, calls_provider"
    ]
  },
  {
    id: "contracts",
    command: "bin/rsocket contracts",
    about: "Какие профили контрактов есть в хранилище. Звёздочкой помечен профиль по умолчанию.",
    lines: [
      "  plain_client     обычный клиент на исключениях",
      "* space_payments   контракт Space Payments (Provider::BaseService)"
    ]
  },
  {
    id: "serve",
    command: "bin/rsocket serve --storage local",
    about:
      "Тот же сборщик, но по HTTP. Сервер печатает свои ручки и выбранное хранилище — по второй строке снизу сразу видно, работает он с диском или с бакетом.",
    lines: [
      "rsocket слушает http://127.0.0.1:9292",
      "  GET  /             — что умеет сервис",
      "  GET  /health       — жив ли он",
      "  GET  /openapi.yaml — описание этого API",
      "  GET  /contracts    — профили контрактов и их роли",
      "  GET  /rules        — что лежит в хранилище правил",
      "  PUT  /rules/<ключ> — записать правила или шаблон",
      "  POST /build        — сборка: ?provider=имя[&contract=профиль], тело — описание",
      "хранилище: local: правила — локальный каталог app/config/rules, результат — каталог output"
    ]
  },
  {
    id: "push",
    command: "bin/rsocket push",
    about:
      "Правила редактируют в репозитории, а сервер читает их из бакета. Команда переносит одно в другое — её же выполняет разовый шаг rules в compose.",
    lines: [
      "правила: локальный каталог /app/app/config/rules → s3://rsocket/rules",
      "  base.yml",
      "  contracts/plain_client/client.rb.erb",
      "  contracts/plain_client/contract.yml",
      "  contracts/plain_client/fixtures.json.erb",
      "  contracts/plain_client/integration.md.erb",
      "  contracts/space_payments/contract.yml",
      "  contracts/space_payments/fixtures.json.erb",
      "  contracts/space_payments/integration.md.erb",
      "  contracts/space_payments/service.rb.erb",
      "перенесено файлов: 9"
    ]
  }
];
