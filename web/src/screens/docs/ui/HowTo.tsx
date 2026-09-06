interface Step {
  title: string;
  text: string;
  code?: string;
}

const CONTRACT_STEPS: Step[] = [
  {
    title: "Описать роли и пороги",
    text: "Контракт называет свои методы сам, а узнаются они по архетипам из base.yml. Порог — минимальный счёт: кандидат ниже порога роль не занимает; обязательная роль без кандидата останавливает сборку.",
    code: `# contracts/plain_client/contract.yml
classification:
  order: [send_payout, payout_state, read_callback, cancel_payout]
  required: [send_payout, payout_state]
  thresholds: { default: 8, send_payout: 10 }
  roles:
    send_payout:
      title: отправка выплаты
      archetype: creation
      traits: [calls_provider, creates_operation]`
  },
  {
    title: "Перевести состояния и ошибки в свой словарь",
    text: "Группы состояний (settled, failed, pending) и семантика ошибок приходят из base.yml — контракт только называет их по-своему. plain_client отдаёт статусы символами и поднимает исключение вместо кода.",
    code: `statuses:
  paid: settled
  declined: failed
  pending: pending

errors:
  default: { code: unknown_error, action: alert }
  semantics:
    credentials: { code: bad_credentials, action: alert }
    rate_limit:  { code: rate_limited, action: retry_backoff }`
  },
  {
    title: "Написать шаблоны и объявить, что печатается",
    text: "Шаблоны .erb получают разбор описания и печатают из него файлы. Список outputs — что профиль печатает на одну сборку.",
    code: `contract:
  title: обычный клиент на исключениях
  class_suffix: Client
  outputs:
    - { template: client.rb.erb, file: "%<provider>s_client.rb" }
    - { template: integration.md.erb, file: INTEGRATION.md }
    - { template: fixtures.json.erb, file: fixtures.json }`
  },
  {
    title: "Положить файлы в хранилище",
    text: "Отдельной команды «создать профиль» нет: профиль — это его файлы. Записали — он виден сразу, правила читаются на каждый запрос.",
    code: `for f in contract.yml client.rb.erb integration.md.erb fixtures.json.erb; do
  curl -X PUT --data-binary @"my_contract/$f" \\
       "http://127.0.0.1:9292/rules/contracts/my_contract/$f"
done
curl -s http://127.0.0.1:9292/health | jq .contracts   # профиль уже виден`
  }
];

const Steps = ({ steps }: { steps: Step[] }) => (
  <ol className="steps">
    {steps.map((step, index) => (
      <li key={step.title}>
        <span className="steps-num mono" aria-hidden="true">
          {index + 1}
        </span>
        <div className="steps-body">
          <h4 className="steps-title">{step.title}</h4>
          <p className="prose-column">{step.text}</p>
          {step.code ? (
            <pre className="ep-code scroll-x" tabIndex={0}>
              <code>{step.code}</code>
            </pre>
          ) : null}
        </div>
      </li>
    ))}
  </ol>
);

export const AddContract = () => (
  <>
    <p className="prose-column doc-lead">
      Профиль контракта — это каталог из <code className="mono">contract.yml</code> и шаблонов.
      В репозитории таких два, и второй, <code className="mono">plain_client</code>, сделан ровно
      затем, чтобы было видно: правила распознавания чужого API от контракта не зависят вовсе.
    </p>
    <Steps steps={CONTRACT_STEPS} />
  </>
);

export const AddRule = () => (
  <>
    <p className="prose-column doc-lead">
      Провайдер называет создание выплаты <code className="mono side-provider">dispatch</code> —
      слова, которого нет ни в одной регулярке. Роль остаётся заглушкой. Чинится это одной
      строкой, и не в коде: в коде инструмента нет ни одного имени операции.
    </p>

    <div className="rule-diff">
      <div>
        <span className="label">было</span>
        <pre className="ep-code" tabIndex={0}>
          <code>{`archetypes:
  creation:
    rules:
      - { field: operation_id, weight: 6,
          pattern: '\\A(create|make|submit|send|issue|register|open|start|initiate|new)' }`}</code>
        </pre>
      </div>
      <div>
        <span className="label">стало</span>
        <pre className="ep-code" tabIndex={0} data-added="true">
          <code>
            {`archetypes:
  creation:
    rules:
      - { field: operation_id, weight: 6,
          pattern: '\\A(create|make|submit|send|issue|register|open|start|initiate|new`}
            <mark className="rule-add">|dispatch</mark>
            {`)' }`}
          </code>
        </pre>
      </div>
    </div>

    <p className="prose-column doc-note">
      Правило добавлено в <code className="mono">base.yml</code> — значит, оно сработает сразу для
      всех контрактов, и для <code className="mono">space_payments</code>, и для{" "}
      <code className="mono">plain_client</code>. Перезапуск не нужен: правила перечитываются на
      каждую сборку. Повторили <code className="mono">POST /build</code> — роль занята.
    </p>

    <pre className="ep-code scroll-x" tabIndex={0}>
      <code>{`curl -X PUT --data-binary @app/config/rules/base.yml \\
     http://127.0.0.1:9292/rules/base.yml
# { "saved": { "key": "base.yml", "kind": "rules", "bytes": 7199 } }`}</code>
    </pre>
  </>
);
