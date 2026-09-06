import { useMemo, useState } from "react";
import { archetypeTitles, fieldTitles } from "~/shared/model/base";
import { candidateOf, matchCandidate } from "~/shared/model/match";
import type { ArchetypeScore } from "~/shared/model/match";
import { SlidingPlate } from "~/shared/ui/SlidingPlate";
import "~/shared/ui/switchtabs.css";

const EXAMPLES = [
  "createPayout",
  "cancelPayout",
  "makeTransfer",
  "getPaymentStatus",
  "revokePaymentOrder"
];

const ArchetypeCard = ({ score, won }: { score: ArchetypeScore; won: boolean }) => (
  <article className="rc-card" data-vetoed={score.vetoed} data-won={won}>
    <header className="rc-card-head">
      <h3 className="rc-card-name mono">{score.name}</h3>
      <p className="rc-card-title">{archetypeTitles[score.name] ?? ""}</p>
      <p className="rc-card-score">
        {score.vetoed ? (
          <span className="rc-veto-score">
            <s>
              {score.rules.reduce((sum, item) => sum + (item.hit ? item.rule.weight : 0), 0)} из{" "}
              {score.possible}
            </s>
            <span className="rc-veto-mark">✕ veto</span>
          </span>
        ) : (
          <>
            <strong>{score.score}</strong>
            <span className="rc-of"> из {score.possible}</span>
          </>
        )}
      </p>
      {won ? <p className="chip chip-contract rc-won">победил</p> : null}
    </header>

    <ul className="rc-rules">
      {score.rules.map((item, index) => (
        <li key={index} className="rc-rule" data-hit={item.hit}>
          <span className="rc-rule-field">{fieldTitles[item.rule.field] ?? item.rule.field}</span>
          <code className="rc-rule-pattern side-provider">{item.rule.pattern}</code>
          <span className="rc-rule-weight mono">{item.hit ? `+${item.rule.weight}` : "0"}</span>
        </li>
      ))}
    </ul>

    {score.veto.some((item) => item.hit) ? (
      <ul className="rc-vetoes">
        {score.veto
          .filter((item) => item.hit)
          .map((item, index) => (
            <li key={index} className="rc-veto">
              <span className="rc-veto-mark" aria-hidden="true">
                ✕
              </span>
              <span>
                снят целиком:{" "}
                <span className="rc-rule-field">
                  {fieldTitles[item.rule.field] ?? item.rule.field}
                </span>{" "}
                совпал с <code className="rc-rule-pattern">{item.rule.pattern}</code>
              </span>
            </li>
          ))}
      </ul>
    ) : null}
  </article>
);

export const RuleCheck = () => {
  const [value, setValue] = useState("cancelPayout");
  const [examples, setExamples] = useState<HTMLDivElement | null>(null);
  const result = useMemo(() => matchCandidate(candidateOf(value.trim() || "operation")), [value]);

  return (
    <div className="rc">
      <div className="rc-input-row">
        <label className="label" htmlFor="rc-field">
          operationId провайдера
        </label>
        <input
          id="rc-field"
          className="rc-input mono"
          value={value}
          spellCheck={false}
          autoComplete="off"
          onChange={(event) => setValue(event.target.value)}
          placeholder="cancelPayout"
        />
        <div
          className="rc-examples switch-sliding"
          role="group"
          aria-label="Готовые примеры"
          ref={setExamples}
        >
          <SlidingPlate
            host={examples}
            activeKey={EXAMPLES.includes(value) ? value : undefined}
            className="switch-slider rc-example-slider"
          />
          {EXAMPLES.map((example) => (
            <button
              key={example}
              type="button"
              className="switch-item mono rc-example"
              aria-pressed={example === value}
              data-active={example === value}
              data-plate={example === value}
              onClick={() => setValue(example)}
            >
              <span className="switch-text">{example}</span>
            </button>
          ))}
        </div>
      </div>

      <p className="rc-derived">
        разбирается как <code className="mono side-provider">{result.candidate.operationId}</code>,
        метод <code className="mono side-provider">{result.candidate.method}</code>, путь{" "}
        <code className="mono side-provider">{result.candidate.path}</code>
        {result.candidate.summary ? (
          <>
            , описание{" "}
            <code className="mono side-provider">{result.candidate.summary}</code>
          </>
        ) : (
          <>. Описания у этой операции нет — правило по нему не сработает</>
        )}
      </p>

      <p className="rc-verdict" aria-live="polite">
        {result.winner ? (
          <>
            архетип{" "}
            <span className="mono side-contract rc-verdict-name">{result.winner.name}</span> —{" "}
            {archetypeTitles[result.winner.name] ?? ""}, счёт{" "}
            <strong>{result.winner.score}</strong>
          </>
        ) : (
          <>ни один архетип не набрал вес: операция осталась бы заглушкой</>
        )}
      </p>

      <div className="rc-grid">
        {result.scores.map((score) => (
          <ArchetypeCard
            key={score.name}
            score={score}
            won={result.winner?.name === score.name}
          />
        ))}
      </div>
    </div>
  );
};
