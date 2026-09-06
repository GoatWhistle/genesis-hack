import type { Report } from "~/shared/api/types";
import { isBound } from "~/shared/api/types";
import { roleTitle } from "~/shared/api/runs";

const Roles = ({ report }: { report: Report }) => (
  <div className="scroll-x" tabIndex={0} role="region" aria-label="Таблица ролей провайдера, прокрутка вбок">
    <table className="tbl">
      <thead>
        <tr>
          <th scope="col">Роль контракта</th>
          <th scope="col">Операция провайдера</th>
          <th scope="col">Счёт</th>
        </tr>
      </thead>
      <tbody>
        {Object.entries(report.roles).map(([name, role]) => (
          <tr key={name}>
            <th scope="row">
              <span className="side-contract mono">{name}</span>
              <span className="cmp-hint">{roleTitle(report.contract, name)}</span>
            </th>
            {isBound(role) ? (
              <>
                <td>
                  <span className="side-provider mono">{role.operation}</span>
                  <span className="cmp-note">{role.endpoint}</span>
                </td>
                <td className="mono num">
                  {role.score} / {role.threshold}
                </td>
              </>
            ) : (
              <td colSpan={2} data-odd="true">
                <span className="stub-mark">заглушка</span>
                <span className="cmp-note">{role.why}</span>
              </td>
            )}
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);

const Statuses = ({ report }: { report: Report }) => (
  <ul className="pairs">
    {Object.entries(report.statuses).map(([from, to]) => (
      <li key={from}>
        <span className="side-provider mono">{from}</span>
        <span className="pairs-arrow" aria-hidden="true">
          →
        </span>
        <span className="side-contract mono">{to}</span>
      </li>
    ))}
  </ul>
);

const CONDITION_SIGN: Record<string, string> = {
  min_amount: "≥",
  max_amount: "≤",
  currency: "∈"
};

const Conditions = ({ report }: { report: Report }) => (
  <ul className="conds">
    {report.conditions.map((cond) => (
      <li key={cond.code}>
        <span className="conds-head">
          <span className="mono side-contract">{cond.code}</span>
          <span className="mono conds-check">
            {cond.checks} {CONDITION_SIGN[cond.kind] ?? "="}{" "}
            <b>{Array.isArray(cond.value) ? cond.value.join(", ") : cond.value}</b>
          </span>
        </span>
        <span className="cmp-hint">{cond.source}</span>
      </li>
    ))}
  </ul>
);

export const ProviderReport = ({ report }: { report: Report }) => (
  <div className="prv-report">
    <section>
      <h3 className="label">Роли и счёт</h3>
      <Roles report={report} />
    </section>

    <div className="prv-cols">
      <section>
        <h3 className="label">Статусы</h3>
        <Statuses report={report} />
      </section>

      <section>
        <h3 className="label">Ограничения из описания</h3>
        {report.conditions.length > 0 ? (
          <Conditions report={report} />
        ) : (
          <p className="cmp-hint">в описании нет ни minimum, ни maximum</p>
        )}
      </section>
    </div>

    <section>
      <h3 className="label">Что инструмент не понял</h3>
      <ul className="notices">
        {report.warnings.map((warning) => (
          <li key={warning} className="notice">
            <span className="notice-mark" aria-hidden="true">
              !
            </span>
            <span>{warning}</span>
          </li>
        ))}
      </ul>
    </section>
  </div>
);
