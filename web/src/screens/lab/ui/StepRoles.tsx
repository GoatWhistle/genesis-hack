import type { Report } from "~/shared/api/types";
import { isBound } from "~/shared/api/types";
import { roleOrder, profileOf } from "~/shared/api/runs";
import { RoleCard } from "./RoleCard";

export const StepRoles = ({ report, contract }: { report: Report; contract: string }) => {
  const order = roleOrder(contract);
  const names = order.length > 0 ? order : Object.keys(report.roles);
  const bound = names.filter((name) => report.roles[name] && isBound(report.roles[name])).length;
  const profile = profileOf(contract);

  return (
    <>
      <p className="prose-column">
        Контракт <span className="side-contract">{profile?.title ?? contract}</span> перечисляет роли, и
        каждая получает операцию не по имени, а по счёту: правила из{" "}
        <code className="mono">base.yml</code> прибавляют вес, порог решает, засчитана роль или нет.
        Ниже — настоящие регулярки, по которым это произошло.
      </p>

      <p className="lab-meta lab-roles-meta">
        <span>
          раздано {bound} из {names.length}
        </span>
        <span>порядок раздачи — сверху вниз, победившая операция уходит из пула</span>
      </p>

      <div className="lab-roles">
        {names.map((name, index) => {
          const role = report.roles[name];
          if (!role) return null;
          return <RoleCard key={`${contract}:${name}`} contract={contract} name={name} role={role} order={index} />;
        })}
      </div>
    </>
  );
};
