import type { Condition, Report } from "~/shared/api/types";
import { useSourceHandlers } from "./useProvenance";

const Plan = ({
  title,
  source,
  children
}: {
  title: string;
  source?: string;
  children: React.ReactNode;
}) => {
  const trace = useSourceHandlers(source ?? "");

  return (
    <article
      className={`panel lab-plan${trace.lit ? " lab-linked" : ""}${trace.known ? " lab-linkable" : ""}`}
      {...trace.props}
    >
      <h3 className="lab-plan-title">
        {title}
        {trace.known ? <span className="lab-linkmark">{trace.label}</span> : null}
      </h3>
      {children}
    </article>
  );
};

const valueText = (value: Condition["value"]) =>
  Array.isArray(value) ? value.join(", ") : String(value);

const ConditionRow = ({ condition }: { condition: Condition }) => {
  const trace = useSourceHandlers(`condition:${condition.code}`);

  return (
  <div
    className={`lab-cond${trace.lit ? " lab-linked" : ""}${trace.known ? " lab-linkable" : ""}`}
    {...trace.props}
  >
    <div className="lab-role-head">
      <span className="chip chip-contract">{condition.code}</span>
      <span className="mono">{valueText(condition.value)}</span>
    </div>
    <p className="mono lab-plan-note">
      {condition.checks}
    </p>
    <p className="lab-source">
      взято из: <span className="side-provider">{condition.source}</span>
    </p>
  </div>
  );
};

export const StepPlans = ({ report }: { report: Report }) => {
  const { amount, conditions, auth, callback } = report;

  return (
    <div className="lab-plans">
      <Plan title="Сумма" source="amount">
        <dl className="lab-facts">
          <dt>множитель</dt>
          <dd className="mono">×{amount.multiplier}</dd>
          <dt>смысл</dt>
          <dd>{amount.note}</dd>
        </dl>
        <p className="lab-source">
          {amount.multiplier === 1 ? (
            <>
              1500 ₽ уйдут провайдеру как <span className="mono">1500</span> — приводить не нужно
            </>
          ) : (
            <>
              1500 ₽ уйдут провайдеру как{" "}
              <span className="mono">{1500 * amount.multiplier}</span>
            </>
          )}
        </p>
      </Plan>

      <Plan title="Ограничения">
        {conditions.length > 0 ? (
          conditions.map((condition) => <ConditionRow key={condition.code} condition={condition} />)
        ) : (
          <p className="lab-meta">Ограничений в описании не нашлось.</p>
        )}
      </Plan>

      <Plan title="Авторизация" source="auth">
        {auth.primary ? (
          <dl className="lab-facts">
            <dt>выбрана</dt>
            <dd className="mono side-provider">{auth.primary}</dd>
            <dt>ещё есть</dt>
            <dd>{auth.alternatives.length > 0 ? auth.alternatives.join(", ") : "нет"}</dd>
          </dl>
        ) : (
          <p className="notice">
            <span className="notice-mark" aria-hidden="true">
              !
            </span>
            Схема не выбрана — выбирать было не из чего.
          </p>
        )}
        {auth.notes.map((note) => (
          <p key={note} className="lab-source">
            {note}
          </p>
        ))}
      </Plan>

      <Plan title="Уведомления" source="callback">
        {callback.supported ? (
          <dl className="lab-facts">
            <dt>подпись</dt>
            <dd className="mono side-provider">{callback.signature_header ?? "не указана"}</dd>
            <dt>алгоритм</dt>
            <dd className="mono">{callback.algorithm ?? "не указан"}</dd>
            <dt>ключ операции</dt>
            <dd className="mono">{callback.operation_id_field ?? "не указан"}</dd>
          </dl>
        ) : (
          <p className="notice">
            <span className="notice-mark" aria-hidden="true">
              !
            </span>
            <span>
              Провайдер не описывает webhook. Роль приёма уведомления осталась заглушкой, состояние
              придётся узнавать опросом.
            </span>
          </p>
        )}
      </Plan>
    </div>
  );
};
