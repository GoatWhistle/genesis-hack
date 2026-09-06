export const LabWarnings = ({ warnings }: { warnings: string[] }) => (
  <section className="band-tight">
    <h2 className="lab-step-title lab-warn-title">Что инструмент не понял</h2>
    <p className="prose-column lab-warn-lead">
      {warnings.length > 0
        ? "Каждая строка — место, где человеку придётся посмотреть глазами. Эти же строки попадают в INTEGRATION.md рядом с кодом."
        : "Инструмент разобрал описание без замечаний."}
    </p>
    <div className="lab-warnings">
      {warnings.map((warning) => (
        <p key={warning} className="notice">
          <span className="notice-mark" aria-hidden="true">
            !
          </span>
          {warning}
        </p>
      ))}
    </div>
  </section>
);
