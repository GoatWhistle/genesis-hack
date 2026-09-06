import { useId, useState } from "react";
import { candidateOf, matchCandidate } from "~/shared/model/match";
import { SlidingPlate } from "~/shared/ui/SlidingPlate";
import "~/shared/ui/switchtabs.css";

const SAMPLES = ["createPayout", "cancelPayout", "payoutWebhook", "getTransferInfo"];

const THRESHOLDS: Record<string, number> = {
  creation: 10,
  status_lookup: 8,
  callback: 8,
  cancellation: 8
};

const ARCHETYPE_TITLES: Record<string, string> = {
  creation: "создание операции",
  status_lookup: "запрос статуса",
  callback: "приём уведомления",
  cancellation: "отмена операции"
};

export const VetoBench = () => {
  const [name, setName] = useState("cancelPayout");
  const [samples, setSamples] = useState<HTMLDivElement | null>(null);
  const fieldId = useId();
  const empty = name.trim() === "";
  const candidate = candidateOf(name);
  const { scores } = matchCandidate(candidate);
  const passing = scores.filter((score) => !score.vetoed && score.score >= (THRESHOLDS[score.name] ?? 8));
  const winner = passing.reduce<(typeof scores)[number] | undefined>(
    (best, item) => (!best || item.score > best.score ? item : best),
    undefined
  );

  return (
    <section className="bench">
      <div className="shell-wide bench-inner">
        <div className="bench-left">
          <h2 className="bench-title">Наберите имя операции — правила ответят сразу</h2>
          <p className="bench-lead">
            Это те самые выражения из <span className="mono">base.yml</span>, что решают судьбу
            настоящего описания. Veto существует потому, что{" "}
            <span className="mono">cancelPayout</span> — это POST со словом{" "}
            <span className="mono">payout</span> в имени, и без него он выиграл бы архетип
            создания.
          </p>

          <label className="bench-field" htmlFor={fieldId}>
            <span className="label">operationId</span>
            <input
              id={fieldId}
              className="bench-input mono"
              type="text"
              value={name}
              spellCheck={false}
              autoComplete="off"
              onChange={(event) => setName(event.target.value)}
            />
          </label>

          <div
            className="bench-samples switch-sliding"
            role="group"
            aria-label="Готовые примеры"
            ref={setSamples}
          >
            <SlidingPlate
              host={samples}
              activeKey={SAMPLES.includes(name) ? name : undefined}
              className="switch-slider bench-slider"
            />
            {SAMPLES.map((sample) => {
              const picked = sample === name;

              return (
                <button
                  type="button"
                  className="switch-item bench-sample"
                  key={sample}
                  aria-pressed={picked}
                  data-active={picked}
                  data-plate={picked}
                  onClick={() => setName(sample)}
                >
                  <span className="switch-text">{sample}</span>
                </button>
              );
            })}
          </div>

          <p className="bench-guess">
            {empty ? (
              "правилам нечего смотреть, пока поле пустое"
            ) : (
              <>
                правила видят{" "}
                <span className="mono side-provider">
                  {candidate.method.toUpperCase()} {candidate.path}
                </span>
                , <span className="mono side-provider">{candidate.operationId}</span>
                {candidate.summary ? (
                  <>
                    {" "}
                    и описание{" "}
                    <span className="mono side-provider">{candidate.summary}</span>
                  </>
                ) : (
                  " — описания у этой операции нет"
                )}
              </>
            )}
          </p>

          <p className="bench-verdict">
            {empty ? (
              "Введите имя операции — или возьмите одно из четырёх выше."
            ) : winner ? (
              <>
                Архетип <span className="mono side-contract">{winner.name}</span> —{" "}
                {ARCHETYPE_TITLES[winner.name] ?? "распознан"}.
              </>
            ) : (
              "Ни один архетип не добрал до порога: такая операция останется заглушкой, а не догадкой."
            )}
          </p>
        </div>

        <ul className="bench-list">
          {scores.map((score) => {
            const vetoHit = score.veto.find((item) => item.hit);
            const ruleHit = score.rules.find((item) => item.hit);
            const threshold = THRESHOLDS[score.name] ?? 8;
            const short = !score.vetoed && score.score < threshold;

            return (
              <li
                className="bench-row"
                key={score.name}
                data-vetoed={score.vetoed}
                data-short={short}
                data-won={score === winner}
              >
                <div className="bench-row-top">
                  <span className="mono bench-arch">{score.name}</span>
                  <span className="bench-score">
                    {score.vetoed ? "снят veto" : `${score.score} при пороге ${threshold}`}
                  </span>
                </div>
                <div className="bench-bar">
                  <span
                    className="bench-bar-fill"
                    style={{ inlineSize: `${(score.score / Math.max(score.possible, 1)) * 100}%` }}
                  />
                  <span
                    className="bench-bar-mark"
                    style={{ insetInlineStart: `${(threshold / Math.max(score.possible, 1)) * 100}%` }}
                  />
                </div>
                <p className="bench-why mono">
                  {vetoHit?.rule.pattern ??
                    (short ? "не добрал до порога" : ruleHit?.rule.pattern) ??
                    "ни одно выражение не совпало"}
                </p>
              </li>
            );
          })}
        </ul>
      </div>
    </section>
  );
};
