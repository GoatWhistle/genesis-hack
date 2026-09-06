import { DECISIONS } from "../model/decisions";

export const Decisions = () => (
  <>
    <p className="prose-column doc-lead">
      Три вопроса, которые задают каждый раз, когда видят раздачу ролей. Ответы касаются устройства
      правил, а не кода: всё, что здесь описано, меняется правкой YAML.
    </p>

    <dl className="doc-asked">
      {DECISIONS.map((item) => (
        <div className="doc-asked-row" key={item.question}>
          <dt>{item.question}</dt>
          <dd>{item.answer}</dd>
        </div>
      ))}
    </dl>
  </>
);
