import { isBound, type Report } from "~/shared/api/types";

interface Operation {
  id: string;
  method: string;
  path: string;
}

export const operationsOf = (report: Report): Operation[] => {
  const seen = new Map<string, Operation>();

  for (const role of Object.values(report.roles)) {
    if (!isBound(role)) continue;
    const [method = "", ...rest] = role.endpoint.split(" ");
    if (seen.has(role.operation)) continue;
    seen.set(role.operation, { id: role.operation, method, path: rest.join(" ") });
  }

  return [...seen.values()];
};

export const StepParse = ({ report }: { report: Report }) => {
  const operations = operationsOf(report);

  return (
    <>
      <p className="prose-column">
        Описание <span className="side-provider">{report.api}</span> разобрано. Ниже операции, которые
        инструмент опознал как относящиеся к делу — метод, путь и <code className="mono">operationId</code>.
        Этот список не меняется при переключении контракта.
      </p>

      <div className="scroll-x" tabIndex={0} role="region" aria-label="Список операций провайдера, прокрутка вбок">
        <div className="lab-ops panel">
          {operations.map((operation) => (
            <div key={operation.id} className="lab-op">
              <span className="lab-op-method">{operation.method}</span>
              <span className="lab-op-path side-provider">{operation.path}</span>
              <span className="lab-op-id mono">{operation.id}</span>
            </div>
          ))}
        </div>
      </div>

      {operations.length === 0 ? (
        <p className="notice">
          <span className="notice-mark" aria-hidden="true">
            !
          </span>
          Ни одна операция описания не набрала порога — смотрите предупреждения в конце.
        </p>
      ) : null}
    </>
  );
};
