import type { Report } from "~/shared/api/types";
import { useSourceHandlers } from "./useProvenance";

const Pair = ({ kind, from, to }: { kind: string; from: string; to: string }) => {
  const trace = useSourceHandlers(`${kind}:${from}`);

  return (
    <div
      className={`lab-dict-row${trace.lit ? " lab-linked" : ""}${trace.known ? " lab-linkable" : ""}`}
      {...trace.props}
    >
      <span className="lab-dict-from">{from}</span>
      <span className="lab-dict-link" aria-hidden="true">
        →
      </span>
      <span className="lab-dict-to">{to}</span>
    </div>
  );
};

const Dictionary = ({ pairs, kind }: { pairs: [string, string][]; kind: string }) => (
  <div className="scroll-x" tabIndex={0} role="region" aria-label="Словарь статусов, прокрутка вбок">
    <div className="lab-dict panel">
      {pairs.map(([from, to]) => (
        <Pair key={from} kind={kind} from={from} to={to} />
      ))}
    </div>
  </div>
);

export const StepStatuses = ({ report }: { report: Report }) => {
  const statuses = Object.entries(report.statuses);
  const events = Object.entries(report.events);

  return (
    <>
      <p className="prose-column">
        Состояния провайдера сведены к состояниям контракта. Слева — слова из описания{" "}
        <span className="side-provider">{report.provider}</span>, справа — то, чем они станут в коде{" "}
        <span className="side-contract">{report.contract}</span>. Несколько чужих слов сходятся в одно
        состояние контракта — регистр при сравнении не важен.
      </p>

      <Dictionary pairs={statuses} kind="status" />

      {statuses.length === 0 ? (
        <p className="notice">
          <span className="notice-mark" aria-hidden="true">
            !
          </span>
          В описании не нашлось перечисления состояний — таблицу придётся заполнить руками.
        </p>
      ) : null}

      {events.length > 0 ? (
        <div className="lab-events">
          <p className="label lab-events-title">События webhook</p>
          <Dictionary pairs={events} kind="event" />
        </div>
      ) : (
        <p className="lab-meta lab-events-none">
          <span>Событий webhook в описании нет — состояние узнаётся опросом.</span>
        </p>
      )}
    </>
  );
};
