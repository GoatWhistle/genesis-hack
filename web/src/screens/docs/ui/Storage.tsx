const ENV: [string, string, string][] = [
  ["RSOCKET_HOST", "127.0.0.1", "адрес, который слушает сервер; в контейнере уже 0.0.0.0"],
  ["RSOCKET_PORT", "9292", "порт"],
  ["RSOCKET_CONTRACT", "space_payments", "профиль контракта по умолчанию"],
  ["RSOCKET_STORAGE", "local для CLI, s3 для сервера", "какое хранилище использовать"],
  ["RSOCKET_RULES_ROOT", "app/config/rules", "каталог с правилами при локальном хранилище"],
  ["RSOCKET_OUTPUT", "output", "каталог результата при локальном хранилище"],
  ["RSOCKET_S3_ENDPOINT", "—", "адрес хранилища, например http://minio:9000"],
  ["RSOCKET_S3_BUCKET", "—", "имя бакета"],
  ["RSOCKET_S3_ACCESS_KEY_ID", "—", "ключ доступа"],
  ["RSOCKET_S3_SECRET_ACCESS_KEY", "—", "секрет"],
  ["RSOCKET_S3_REGION", "us-east-1", "регион подписи; для MinIO подойдёт любой"],
  ["RSOCKET_S3_RULES_PREFIX", "rules", "префикс ключей правил в бакете"],
  ["RSOCKET_S3_OUTPUT_PREFIX", "output", "префикс ключей результата"]
];

export const Storage = () => (
  <>
    <p className="prose-column doc-lead">
      Правила и результат сборки лежат в хранилище, которое выбирается при запуске. Командная
      строка работает локально, сервер — через S3; оба умолчания перекрываются флагом{" "}
      <code className="mono">--storage</code> или переменной <code className="mono">RSOCKET_STORAGE</code>.
      S3 можно не использовать вовсе: с <code className="mono">RSOCKET_STORAGE=local</code> сервер
      работает с диском, и для запуска не нужно ничего, кроме репозитория.
    </p>

    <div className="scroll-x" tabIndex={0} role="region" aria-label="Таблица, прокрутка вбок">
      <table className="doc-tbl">
        <thead>
          <tr>
            <th scope="col" />
            <th scope="col">Правила</th>
            <th scope="col">Результат</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <th scope="row" className="mono">local</th>
            <td className="mono">app/config/rules/</td>
            <td className="mono">output/&lt;provider&gt;/</td>
          </tr>
          <tr>
            <th scope="row" className="mono">s3</th>
            <td className="mono">{"s3://<бакет>/rules/"}</td>
            <td className="mono">{"s3://<бакет>/output/<provider>/"}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <p className="prose-column doc-note">
      Правила читаются на каждый запрос, поэтому правка действует немедленно — и когда файл
      поправили на диске, и когда его записали ручкой <code className="mono">PUT /rules/&lt;ключ&gt;</code>.
      Если S3 выбран, но не настроен, сервис не поднимется и скажет, каких переменных не хватает,
      вместо того чтобы упасть на первом запросе.
    </p>

    <h3 className="doc-h3">Переменные окружения</h3>
    <div className="scroll-x" tabIndex={0} role="region" aria-label="Таблица, прокрутка вбок">
      <table className="doc-tbl">
        <thead>
          <tr>
            <th scope="col">Переменная</th>
            <th scope="col">По умолчанию</th>
            <th scope="col">Что задаёт</th>
          </tr>
        </thead>
        <tbody>
          {ENV.map(([name, fallback, what]) => (
            <tr key={name}>
              <th scope="row" className="mono">{name}</th>
              <td className="mono doc-default">{fallback}</td>
              <td>{what}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>

    <h3 className="doc-h3">compose.yaml</h3>
    <p className="prose-column doc-note">
      Стек поднимает три вещи: MinIO как S3-хранилище, разовый шаг <code className="mono">rules</code>{" "}
      (он переносит локальные правила в бакет командой <code className="mono">push</code>) и сам
      сервер. Консоль MinIO — на <code className="mono">localhost:9001</code>, логин и пароль{" "}
      <code className="mono">rsocket</code> / <code className="mono">rsocket-secret</code>.
    </p>
    <pre className="ep-code scroll-x" tabIndex={0}>
      <code>{`docker compose up --build      # MinIO + сервер на localhost:9292
docker compose logs -f rsocket # что происходит
docker compose down            # остановить

# разовая сборка тем же образом, без поднятия сервера
docker compose run --rm rsocket \\
  bundle exec bin/rsocket build -s examples/novapay/provider_api.yaml -p novapay -o output`}</code>
    </pre>
  </>
);
