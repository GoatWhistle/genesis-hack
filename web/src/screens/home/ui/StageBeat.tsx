import type { StageBeat } from "../model/stage";

const clamp01 = (value: number) => Math.min(1, Math.max(0, value));

export const OperationCard = ({ beat, local }: { beat: StageBeat; local: number }) => (
  <div className="stage-op" data-flown={local > 0.72}>
    <span className="stage-op-verb">{beat.verb}</span>
    <span className="stage-op-path">{beat.path}</span>
    <span className="stage-op-id mono">{beat.operation}</span>
    <span className="stage-op-wire" style={{ transform: `scaleX(${clamp01((local - 0.5) * 3)})` }} />
  </div>
);

export const RivalList = ({ beat, local }: { beat: StageBeat; local: number }) => (
  <ul className="stage-rivals">
    {beat.rivals.map((rival, index) => {
      const at = clamp01((local - 0.14 - index * 0.05) * 9);
      return (
        <li
          className="stage-rival"
          key={rival.operation}
          data-out={rival.vetoed && at > 0.5}
          style={{ opacity: 0.86 + at * 0.14, transform: `translateX(${(1 - at) * 4}px)` }}
        >
          <span className="mono">{rival.operation}</span>
          <span className="stage-rival-score">
            {rival.vetoed ? "veto" : `${rival.score} из ${rival.possible}`}
          </span>
        </li>
      );
    })}
  </ul>
);

export const ScoreMeter = ({ beat, local }: { beat: StageBeat; local: number }) => {
  const grown = clamp01((local - 0.16) * 2.6);
  const shown = Math.round(beat.score * grown);
  const ceiling = Math.max(beat.score, beat.threshold) * 1.25;

  return (
    <div className="stage-meter">
      <p className="stage-meter-arch mono">архетип {beat.archetype}</p>
      <div className="stage-meter-track">
        <span className="stage-meter-fill" style={{ inlineSize: `${(shown / ceiling) * 100}%` }} />
        <span
          className="stage-meter-mark"
          style={{ insetInlineStart: `${(beat.threshold / ceiling) * 100}%` }}
        />
      </div>
      <p className="stage-meter-read">
        счёт <b>{shown}</b> при пороге {beat.threshold}
      </p>
    </div>
  );
};

export const RuleList = ({ beat, local }: { beat: StageBeat; local: number }) => (
  <ul className="stage-rules">
    {beat.rules.map((rule, index) => {
      const at = clamp01((local - 0.2 - index * 0.055) * 9);
      return (
        <li
          className="stage-rule"
          key={rule.pattern}
          style={{ opacity: at < 0.5 ? 0 : 1, transform: `translateX(${(1 - at) * 6}px)` }}
        >
          <span className="stage-rule-field">{rule.field}</span>
          <span className="stage-rule-pattern">{rule.pattern}</span>
        </li>
      );
    })}
  </ul>
);

export const CodeColumn = ({ beat, local }: { beat: StageBeat; local: number }) => (
  <div className="scroll-x" tabIndex={0} role="region" aria-label="Сгенерированный код, прокрутка вбок">
    <pre className="stage-code">
      {beat.code.map((line, index) => {
        const at = clamp01((local - 0.58 - index * 0.032) * 12);
        return (
          <span
            className="stage-code-line"
            key={`${beat.role}-${index}`}
            style={{ opacity: at < 0.5 ? 0 : 1, transform: `translateX(${(1 - at) * 8}px)` }}
          >
            {line === "" ? " " : line}
          </span>
        );
      })}
    </pre>
  </div>
);
