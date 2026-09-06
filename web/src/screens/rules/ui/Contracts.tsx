import { archetypeTitles } from "~/shared/model/base";
import { archetypeRoleMap, contractViews } from "../model/contractModel";

export const ContractBridge = () => {
  const views = contractViews();
  const rows = archetypeRoleMap();

  return (
    <div className="scroll-x" tabIndex={0} role="region" aria-label="Таблица архетипов и ролей, прокрутка вбок">
      <table className="ctr-table">
        <thead>
          <tr>
            <th scope="col" className="ctr-th-arch">
              архетип из <span className="mono">base.yml</span>
            </th>
            {views.map((view) => (
              <th key={view.name} scope="col">
                <span className="mono side-contract">{view.name}</span>
                <span className="ctr-th-title">{view.title}</span>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.archetype}>
              <th scope="row" className="ctr-arch">
                <span className="mono">{row.archetype}</span>
                <span className="ctr-arch-title">{archetypeTitles[row.archetype] ?? ""}</span>
              </th>
              {views.map((view) => {
                const role = row.byContract[view.name];
                return (
                  <td key={view.name}>
                    {role ? (
                      <>
                        <code className="mono side-contract ctr-role">{role.name}</code>
                        <span className="ctr-role-title">{role.title}</span>
                        <span className="ctr-role-meta mono">
                          порог {role.threshold}
                          {role.required ? " · обязательна" : ""}
                        </span>
                      </>
                    ) : (
                      <span className="ctr-none">—</span>
                    )}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

export const ContractStatuses = () => {
  const views = contractViews();
  const groups = ["settled", "failed", "pending"];

  return (
    <div className="scroll-x" tabIndex={0} role="region" aria-label="Таблица контракта, прокрутка вбок">
      <table className="ctr-table">
        <thead>
          <tr>
            <th scope="col" className="ctr-th-arch">
              группа состояний
            </th>
            {views.map((view) => (
              <th key={view.name} scope="col">
                <span className="mono side-contract">{view.name}</span>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {groups.map((group) => (
            <tr key={group}>
              <th scope="row" className="ctr-arch">
                <span className="mono">{group}</span>
              </th>
              {views.map((view) => {
                const own = view.statuses.find((item) => item.group === group);
                return (
                  <td key={view.name}>
                    {own ? (
                      <code className="mono side-contract ctr-role">{own.own}</code>
                    ) : (
                      <span className="ctr-none">—</span>
                    )}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
