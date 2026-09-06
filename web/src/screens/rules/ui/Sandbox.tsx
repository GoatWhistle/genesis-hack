import { useState } from "react";
import { archetypeTitles, fieldTitles } from "~/shared/model/base";
import { assign, cloneArchetypes, sandboxProviders, thresholds, withPatchedRule } from "../model/sandboxModel";
import { SwitchTabs } from "~/shared/ui/SwitchTabs";

const ORIGINAL = cloneArchetypes();
const BASELINE = assign(ORIGINAL);

export const Sandbox = () => {
  const [archetype, setArchetype] = useState(ORIGINAL[0]?.name ?? "creation");
  const [ruleIndex, setRuleIndex] = useState(0);
  const [weight, setWeight] = useState<number | undefined>();
  const [pattern, setPattern] = useState<string | undefined>();

  const picked = ORIGINAL.find((item) => item.name === archetype) ?? ORIGINAL[0];
  const rule = picked?.rules[ruleIndex];
  const currentWeight = weight ?? rule?.weight ?? 0;
  const currentPattern = pattern ?? rule?.pattern ?? "";
  const ruleName = rule ? (fieldTitles[rule.field] ?? rule.field) : "";
  const touched = (weight !== undefined && weight !== rule?.weight) || pattern !== undefined;

  const before = BASELINE;
  const after = assign(
    withPatchedRule(ORIGINAL, archetype, ruleIndex, {
      weight: currentWeight,
      pattern: currentPattern
    })
  );

  const pick = (name: string) => {
    setArchetype(name);
    setRuleIndex(0);
    setWeight(undefined);
    setPattern(undefined);
  };

  const pickRule = (index: number) => {
    setRuleIndex(index);
    setWeight(undefined);
    setPattern(undefined);
  };

  return (
    <div className="sbx">
      <div className="sbx-controls">
        <div className="sbx-control">
          <span className="label">архетип</span>
          <div className="scroll-x">
            <SwitchTabs
              label="Архетип"
              group="sbx-archetype"
              role="group"
              options={ORIGINAL.map((item) => ({ id: item.name, label: item.name }))}
              current={archetype}
              onPick={pick}
            />
          </div>
        </div>

        <div className="sbx-control">
          <span className="label">правило</span>
          <div className="sbx-rule-list" role="group" aria-label="Правило">
            {(picked?.rules ?? []).map((item, index) => (
              <button
                key={index}
                type="button"
                className="sbx-rule-pick"
                aria-pressed={index === ruleIndex}
                aria-label={`${fieldTitles[item.field] ?? item.field}, вес ${item.weight}`}
                data-active={index === ruleIndex}
                onClick={() => pickRule(index)}
              >
                <span className="sbx-rule-field">{fieldTitles[item.field] ?? item.field}</span>
                <code className="sbx-rule-pattern">{item.pattern}</code>
                <span className="mono sbx-rule-w">{item.weight}</span>
              </button>
            ))}
          </div>
        </div>

        <div className="sbx-control sbx-edit">
          <label className="label" htmlFor="sbx-weight">
            вес: <strong className="mono">{currentWeight}</strong>
          </label>
          <input
            id="sbx-weight"
            className="sbx-range"
            type="range"
            min={0}
            max={10}
            value={currentWeight}
            aria-label={`Вес правила «${ruleName}» в архетипе ${archetype}`}
            aria-valuetext={`${currentWeight} из 10`}
            onChange={(event) => setWeight(Number(event.target.value))}
          />
          <label className="label" htmlFor="sbx-pattern">
            регулярка
          </label>
          <input
            id="sbx-pattern"
            className="rc-input mono"
            value={currentPattern}
            spellCheck={false}
            autoComplete="off"
            aria-label={`Регулярка правила «${ruleName}» в архетипе ${archetype}`}
            onChange={(event) => setPattern(event.target.value)}
          />
          <button
            type="button"
            className="btn btn-ghost sbx-reset"
            disabled={!touched}
            onClick={() => {
              setWeight(undefined);
              setPattern(undefined);
            }}
          >
            вернуть как в base.yml
          </button>
        </div>
      </div>

      <div className="scroll-x">
        <table className="sbx-table">
          <thead>
            <tr>
              <th scope="col">архетип</th>
              {sandboxProviders.map((provider) => (
                <th key={provider} scope="col" className="mono side-provider">
                  {provider}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {ORIGINAL.map((item) => (
              <tr key={item.name}>
                <th scope="row" className="sbx-arch">
                  <span className="mono">{item.name}</span>
                  <span className="sbx-arch-title">{archetypeTitles[item.name] ?? ""}</span>
                  <span className="sbx-arch-th mono">порог {thresholds[item.name] ?? 8}</span>
                </th>
                {sandboxProviders.map((provider, index) => {
                  const was = before[index]?.byArchetype[item.name];
                  const now = after[index]?.byArchetype[item.name];
                  const changed = was?.operationId !== now?.operationId || was?.score !== now?.score;

                  return (
                    <td key={provider} data-changed={changed}>
                      {changed && was ? (
                        <s className="sbx-was mono">
                          {was.operationId} · {was.score}
                        </s>
                      ) : null}
                      {now ? (
                        <span className="sbx-now mono">
                          {now.operationId} <span className="sbx-now-score">· {now.score}</span>
                        </span>
                      ) : (
                        <span className="sbx-empty">заглушка</span>
                      )}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <p className="sbx-hint label" aria-live="polite">
        {touched
          ? "перечёркнуто — как было по base.yml, ниже — как стало бы с вашей правкой"
          : "правила пока не тронуты: таблица показывает раздачу ролей как есть"}
      </p>
    </div>
  );
};
