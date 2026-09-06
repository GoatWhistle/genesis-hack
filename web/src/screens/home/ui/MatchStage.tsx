import { useState } from "react";
import type { PageProps } from "~/layout/types";
import { providers, roleOrder } from "~/shared/api/runs";
import { isBound } from "~/shared/api/types";
import { useBakedRun } from "~/shared/api/useRun";

const CONTRACT = "space_payments";
const DEFAULT_PROVIDER = "kassabox";

const displayName = (provider: string) => {
  const names: Record<string, string> = {
    kassabox: "KassaBox",
    nordbank: "Nordbank",
    novapay: "NovaPay",
    swiftpay: "SwiftPay"
  };

  return names[provider] ?? provider;
};

const outputName = (provider: string, files: Record<string, string>) =>
  Object.keys(files).find((name) => name.endsWith("_service.rb")) ??
  Object.keys(files)[0] ??
  `${provider}_service.rb`;

const sourcePreview = (source: string, method: string | undefined) => {
  const lines = source.split("\n");
  const start = method
    ? lines.findIndex((line) => new RegExp(`^\\s*def ${method}\\b`).test(line))
    : -1;
  if (start < 0) return lines.slice(0, 9).join("\n");

  const indent = lines[start]?.match(/^\s*/)?.[0].length ?? 0;
  return lines
    .slice(start, start + 8)
    .map((line) => line.slice(indent))
    .join("\n");
};

export const MatchStage = ({ go }: PageProps) => {
  const [provider, setProvider] = useState(DEFAULT_PROVIDER);
  const { run, loading, error } = useBakedRun(provider, CONTRACT);
  const roles = run
    ? roleOrder(CONTRACT).flatMap((name) => {
        const role = run.report.roles[name];
        return role ? [{ name, role }] : [];
      })
    : [];
  const mapped = roles.filter(({ role }) => isBound(role));
  const fileName = run ? outputName(run.provider, run.files) : "service.rb";
  const preview = run ? sourcePreview(run.files[fileName] ?? "", mapped[0]?.name) : "";

  return (
    <section className="stage" aria-labelledby="demo-title">
      <div className="shell-wide stage-inner">
        <header className="stage-head">
          <div>
            <p className="stage-kicker">Готовый прогон · без загрузки и настройки</p>
            <h1 className="stage-title" id="demo-title">
              Из чужого OpenAPI — <span className="side-contract">готовый сервис</span> под ваш
              контракт
            </h1>
            <p className="stage-lead">
              Выберите демо-документ: мы сразу покажем, какие операции распознали и какой код
              собрали. Это настоящий результат генератора, а не макет.
            </p>
          </div>
          <div className="stage-cta">
            <button type="button" className="btn btn-primary" onClick={() => go("/lab")}>
              Разобрать свой документ
              <span aria-hidden="true">→</span>
            </button>
            <span>OpenAPI в YAML или JSON</span>
          </div>
        </header>

        <div className="stage-picker" aria-label="Демо-документ">
          <span className="stage-picker-label">Показать на примере</span>
          <div className="stage-picker-options">
            {providers.map((item) => (
              <button
                type="button"
                className="stage-pick"
                key={item}
                aria-pressed={provider === item}
                onClick={() => setProvider(item)}
              >
                {displayName(item)}
              </button>
            ))}
          </div>
        </div>

        {error ? (
          <p className="notice" role="alert">
            <span className="notice-mark">!</span>
            Не удалось открыть демо-прогон: {error}
          </p>
        ) : null}

        <div className="stage-grid" aria-busy={loading}>
          <article className="stage-card stage-card-input">
            <header className="stage-card-head">
              <span className="stage-step">01</span>
              <div>
                <p className="stage-card-label">На входе</p>
                <h2>Документация провайдера</h2>
              </div>
            </header>

            {run ? (
              <div className="stage-card-body">
                <div className="stage-document">
                  <span className="stage-document-type">OpenAPI</span>
                  <strong>{run.report.api}</strong>
                  <span className="mono">{run.report.base_url ?? "URL задаётся окружением"}</span>
                </div>
                <ul className="stage-endpoints" aria-label="Операции из документа">
                  {mapped.map(({ name, role }) =>
                    isBound(role) ? (
                      <li key={name}>
                        <span className="stage-verb">{role.endpoint.split(" ")[0]}</span>
                        <code>{role.endpoint.split(" ").slice(1).join(" ")}</code>
                      </li>
                    ) : null
                  )}
                </ul>
              </div>
            ) : (
              <p className="stage-loading">Открываем демо-документ…</p>
            )}
          </article>

          <article className="stage-card stage-card-decisions">
            <header className="stage-card-head">
              <span className="stage-step">02</span>
              <div>
                <p className="stage-card-label">Генератор решает</p>
                <h2>Что чему соответствует</h2>
              </div>
            </header>

            {run ? (
              <div className="stage-card-body">
                <ul className="stage-decisions">
                  {roles.map(({ name, role }) => (
                    <li key={name} data-bound={isBound(role)}>
                      <span className="stage-decision-main">
                        <code className="side-provider">
                          {isBound(role) ? role.operation : "не найдено"}
                        </code>
                        <span aria-hidden="true">→</span>
                        <code className="side-contract">{name}</code>
                      </span>
                      <span className="stage-decision-meta">
                        {isBound(role)
                          ? `${role.score} баллов при пороге ${role.threshold}`
                          : role.why}
                      </span>
                    </li>
                  ))}
                </ul>
                <div className="stage-facts">
                  <span>сумма × {run.report.amount.multiplier}</span>
                  <span>{run.report.auth.primary ?? "авторизация не найдена"}</span>
                </div>
              </div>
            ) : (
              <p className="stage-loading">Сопоставляем операции…</p>
            )}
          </article>

          <article className="stage-card stage-card-result">
            <header className="stage-card-head">
              <span className="stage-step">03</span>
              <div>
                <p className="stage-card-label">На выходе</p>
                <h2>Сервис под контракт</h2>
              </div>
            </header>

            {run ? (
              <div className="stage-card-body">
                <div className="stage-result-summary">
                  <strong>{Object.keys(run.files).length} готовых файла</strong>
                  <span>
                    {mapped.length} из {roles.length} ролей реализованы автоматически
                  </span>
                </div>
                <div className="stage-code-preview">
                  <div className="stage-code-head">
                    <span className="mono">{fileName}</span>
                    <span>Ruby</span>
                  </div>
                  <pre>
                    <code>{preview}</code>
                  </pre>
                </div>
                {run.warnings.length > 0 ? (
                  <p className="stage-review">
                    <span>Нужна проверка человека</span>
                    {run.warnings[0]}
                  </p>
                ) : null}
              </div>
            ) : (
              <p className="stage-loading">Собираем сервис…</p>
            )}
          </article>
        </div>

        <p className="stage-footnote">
          <span className="side-provider">Документ провайдера</span>
          <span aria-hidden="true">→</span>
          <span>объяснимые правила</span>
          <span aria-hidden="true">→</span>
          <span className="side-contract">контракт вашего приложения</span>
        </p>
      </div>
    </section>
  );
};
