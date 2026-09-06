import type { BaseRules, FieldGroup } from "~/shared/model/base";

const STATUS_TITLES: Record<string, string> = {
  settled: "деньги дошли",
  failed: "операция не прошла",
  pending: "ещё в работе"
};

const GROUP_TITLES: Record<string, string> = {
  payloadPatterns: "поля тела запроса",
  requisitePatterns: "реквизиты получателя",
  pathPatterns: "параметры пути",
  callbackFields: "поля тела webhook",
  headers: "заголовки"
};

export const StatusGroups = ({ base }: { base: BaseRules }) => (
  <div className="dict-statuses">
    {base.statusPatterns.map((group) => (
      <section key={group.group} className="dict-status">
        <h3 className="dict-status-name mono side-contract">{group.group}</h3>
        <p className="dict-status-title">{STATUS_TITLES[group.group] ?? ""}</p>
        {group.patterns.map((pattern, index) => (
          <code key={index} className="dict-pattern side-provider">
            {pattern}
          </code>
        ))}
      </section>
    ))}
  </div>
);

export const ErrorSemantics = ({ base }: { base: BaseRules }) => (
  <div className="scroll-x" tabIndex={0} role="region" aria-label="Таблица словаря, прокрутка вбок">
    <table className="dict-table dict-errors">
      <thead>
        <tr>
          <th scope="col">код</th>
          <th scope="col">смысл</th>
        </tr>
      </thead>
      <tbody>
        {base.errorSemantics.map((item) => (
          <tr key={item.code}>
            <td className="mono side-provider">{item.code}</td>
            <td className="mono">{item.meaning}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);

export const FieldPatterns = ({ title, groups }: { title: string; groups: FieldGroup[] }) => (
  <section className="dict-fields" aria-label={title}>
    <h3 className="dict-fields-title label">{title}</h3>
    <div className="scroll-x" tabIndex={0} role="region" aria-label="Таблица словаря, прокрутка вбок">
      <table className="dict-table">
        <tbody>
          {groups.map((group) => (
            <tr key={group.field}>
              <td className="dict-field mono">{group.field}</td>
              <td className="dict-field-patterns">
                {group.patterns.map((pattern, index) => (
                  <code key={index} className="dict-pattern side-provider">
                    {pattern}
                  </code>
                ))}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  </section>
);

export const AllFieldPatterns = ({ base }: { base: BaseRules }) => (
  <div className="dict-field-blocks">
    <FieldPatterns title={GROUP_TITLES.payloadPatterns ?? ""} groups={base.payloadPatterns} />
    <FieldPatterns title={GROUP_TITLES.requisitePatterns ?? ""} groups={base.requisitePatterns} />
    <FieldPatterns title={GROUP_TITLES.callbackFields ?? ""} groups={base.callbackFields} />
    <FieldPatterns title={GROUP_TITLES.headers ?? ""} groups={base.headers} />
    <FieldPatterns title={GROUP_TITLES.pathPatterns ?? ""} groups={base.pathPatterns} />
  </div>
);

export const AmountUnits = ({ base }: { base: BaseRules }) => (
  <div className="dict-amount">
    <div className="dict-amount-main">
      <p className="label">слова, по которым сумма считается копейками</p>
      <div className="dict-amount-patterns">
        {base.amountUnits.minorPatterns.map((pattern, index) => (
          <code key={index} className="dict-pattern side-provider">
            {pattern}
          </code>
        ))}
      </div>
      <p className="dict-amount-mult">
        множитель <strong className="mono">{base.amountUnits.multiplier}</strong>
      </p>
    </div>

    {base.amountUnits.minorRequiresInteger ? (
      <div className="notice dict-amount-note">
        <span className="notice-mark" aria-hidden="true">
          !
        </span>
        <span>
          <code className="mono">minor_requires_integer: true</code> — копейки признаются только
          у целочисленного поля. Слово «копейки» в описании строковой суммы («рубли и копейки
          через точку») говорит о формате записи, а не о единицах: без этой проверки{" "}
          <span className="mono">1500.00</span> рублей уехало бы в{" "}
          <s className="mono">150000</s> рублей.
        </span>
      </div>
    ) : null}

    <div className="scroll-x" tabIndex={0} role="region" aria-label="Таблица словаря, прокрутка вбок">
      <table className="dict-table">
        <thead>
          <tr>
            <th scope="col">граница</th>
            <th scope="col">сравнение</th>
            <th scope="col">регулярка по описанию</th>
          </tr>
        </thead>
        <tbody>
          {base.amountTextRules.map((rule, index) => (
            <tr key={index}>
              <td className="mono">{rule.kind}</td>
              <td className="mono dict-comparison">{rule.comparison}</td>
              <td>
                <code className="dict-pattern side-provider">{rule.pattern}</code>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  </div>
);
