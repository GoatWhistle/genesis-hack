import { archetypeTitles, fieldTitles } from "~/shared/model/base";
import type { Archetype } from "~/shared/model/base";

const WeightBar = ({ weight, max }: { weight: number; max: number }) => (
  <span
    className="arc-weight-bar"
    style={{ inlineSize: `${Math.max(6, (weight / max) * 100)}%` }}
    aria-hidden="true"
  />
);

export const ArchetypeBlock = ({ archetype }: { archetype: Archetype }) => {
  const max = archetype.rules.reduce((top, rule) => Math.max(top, rule.weight), 1);
  const total = archetype.rules.reduce((sum, rule) => sum + rule.weight, 0);

  return (
    <section className="arc" aria-labelledby={`arc-${archetype.name}`}>
      <header className="arc-head">
        <h3 id={`arc-${archetype.name}`} className="arc-name mono">
          {archetype.name}
        </h3>
        <p className="arc-title">{archetypeTitles[archetype.name] ?? ""}</p>
        <p className="arc-total mono">максимум {total}</p>
      </header>

      <table className="arc-table">
        <thead>
          <tr>
            <th scope="col">поле</th>
            <th scope="col">регулярка</th>
            <th scope="col" className="arc-th-weight">
              вес
            </th>
          </tr>
        </thead>
        <tbody>
          {archetype.rules.map((rule, index) => (
            <tr key={index}>
              <td className="arc-field">{fieldTitles[rule.field] ?? rule.field}</td>
              <td>
                <code className="arc-pattern side-provider">{rule.pattern}</code>
              </td>
              <td className="arc-weight">
                <span className="arc-weight-cell">
                  <WeightBar weight={rule.weight} max={max} />
                  <span className="mono arc-weight-num">{rule.weight}</span>
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {archetype.veto.length > 0 ? (
        <div className="arc-veto-block">
          <p className="label arc-veto-label">
            <span className="rc-veto-mark" aria-hidden="true">
              ✕
            </span>{" "}
            veto — снимают кандидата целиком, счёт не считается
          </p>
          <ul className="arc-veto-list">
            {archetype.veto.map((rule, index) => (
              <li key={index}>
                <span className="arc-field">{fieldTitles[rule.field] ?? rule.field}</span>{" "}
                <code className="arc-pattern arc-pattern-veto">{rule.pattern}</code>
              </li>
            ))}
          </ul>
        </div>
      ) : (
        <p className="arc-veto-none label">veto нет — архетип ничем не отменяется</p>
      )}
    </section>
  );
};
