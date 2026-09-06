import { useBakedRun } from "~/shared/api/useRun";
import { isBound } from "~/shared/api/types";

export const HonestySection = () => {
  const { run } = useBakedRun("nordbank", "space_payments");
  if (!run) return null;

  const stubs = Object.entries(run.report.roles).filter(([, role]) => !isBound(role));
  const stub = stubs[0];
  const why = stub && !isBound(stub[1]) ? stub[1].why : undefined;

  return (
    <section className="honest">
      <div className="shell-wide honest-inner">
        <div className="honest-say">
          <h2 className="honest-title">
            Про <span className="mono side-provider">nordbank</span> инструмент честно сказал, чего
            не знает
          </h2>
          <p className="honest-lead">
            Описание неполное. Догадка выглядела бы как рабочий код и упала бы на проде, поэтому
            вместо неё — эти строки в отчёте и явная заглушка в классе.
          </p>
          {stub ? (
            <p className="honest-stub">
              Роль <span className="mono side-contract">{stub[0]}</span> осталась заглушкой:{" "}
              {why ?? "кандидат не добрал до порога"}.
            </p>
          ) : null}
        </div>

        <ol className="honest-list">
          {run.report.warnings.map((warning) => (
            <li className="honest-line" key={warning}>
              <span className="honest-mark" aria-hidden="true">
                !
              </span>
              <span>{warning}</span>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
};
