import { useState } from "react";
import type { ContractProfile, ContractRole } from "~/shared/api/types";
import { profiles } from "~/shared/api/runs";

const TRAIT_HINTS: Record<string, string> = {
  calls_provider: "роль сама ходит в API провайдера",
  creates_operation: "роль заводит новую операцию у провайдера",
  receives_callback: "роль принимает уведомление от провайдера"
};

const allTraits = (list: ContractProfile[]): string[] => {
  const seen = new Set<string>();
  for (const profile of list) {
    for (const role of profile.roles) for (const trait of role.traits) seen.add(trait);
  }
  return [...seen];
};

const RoleRow = ({ role, trait }: { role: ContractRole; trait: string | undefined }) => {
  const lit = trait !== undefined && role.traits.includes(trait);
  return (
    <div className="role-row" data-lit={lit} data-dim={trait !== undefined && !lit}>
      <div className="role-name">{role.name}</div>
      <div className="role-meta">
        {role.title} · порог {role.threshold}
        {role.required ? " · обязательная" : " · необязательная"}
      </div>
    </div>
  );
};

export const LayersSection = () => {
  const [trait, setTrait] = useState<string | undefined>(undefined);
  const traits = allTraits(profiles);

  return (
    <section className="shell-wide band layers-band">
      <div className="layers">
        <div className="layers-say">
          <h2 className="layers-title">Знание лежит в двух слоях, а не в коде</h2>
          <p className="layers-lead">
            <span className="mono">base.yml</span> знает, как чужие API называют одно и то же.
            Профиль контракта знает, под какой интерфейс мы собираем. Кода про платежи в
            инструменте нет вовсе.
          </p>
          <div className="trait-list">
            {traits.map((name) => (
              <button
                type="button"
                className="trait-item"
                key={name}
                aria-pressed={trait === name}
                data-active={trait === name}
                onMouseEnter={() => setTrait(name)}
                onMouseLeave={() => setTrait(undefined)}
                onFocus={() => setTrait(name)}
                onBlur={() => setTrait(undefined)}
                onClick={() => setTrait(trait === name ? undefined : name)}
              >
                <span className="trait-name">{name}</span>
                <span className="trait-hint">{TRAIT_HINTS[name] ?? "признак роли"}</span>
              </button>
            ))}
          </div>
        </div>

        <div className="layers-show">
          <div className="contract-pair">
            {profiles.map((profile) => (
              <div className="contract-col" key={profile.name}>
                <h3 className="mono side-contract">{profile.name}</h3>
                <p>{profile.title}</p>
                {profile.roles.map((role) => (
                  <RoleRow role={role} trait={trait} key={role.name} />
                ))}
              </div>
            ))}
          </div>
          <p className="home-note layers-hint">
            Наведите на признак слева — подсветятся роли обоих контрактов, которые его требуют.
            Имена ролей разные, требование к операции одно.
          </p>
        </div>
      </div>
    </section>
  );
};
