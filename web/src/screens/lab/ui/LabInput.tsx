import { providers, profiles } from "~/shared/api/runs";
import type { BuildOutcome } from "~/shared/api/types";
import { SwitchTabs } from "~/shared/ui/SwitchTabs";

interface LabInputProps {
  provider: string;
  contract: string;
  onProvider: (value: string) => void;
  onContract: (value: string) => void;
  run: BuildOutcome | undefined;
}

const Switch = ({
  legend,
  items,
  value,
  onPick,
  group
}: {
  legend: string;
  items: { name: string; title: string }[];
  value: string;
  onPick: (next: string) => void;
  group: string;
}) => (
  <div className="lab-input-group">
    <span className="label">{legend}</span>
    <SwitchTabs
      label={legend}
      group={group}
      role="group"
      options={items.map((item) => ({ id: item.name, label: item.name, title: item.title }))}
      current={value}
      onPick={onPick}
    />
  </div>
);

export const LabInput = ({ provider, contract, onProvider, onContract, run }: LabInputProps) => (
  <div className="lab-input">
    <div className="shell-wide lab-input-inner">
      <Switch
        legend="Описание"
        items={providers.map((name) => ({ name, title: `Разобрать описание ${name}` }))}
        value={provider}
        onPick={onProvider}
        group="lab-provider"
      />
      <Switch
        legend="Контракт"
        items={profiles.map((profile) => ({ name: profile.name, title: profile.title }))}
        value={contract}
        onPick={onContract}
        group="lab-contract"
      />
      <div className="lab-meta lab-input-spacer">
        {run ? (
          <>
            <span className="side-provider">{run.report.api}</span>
            <span className="mono">{run.report.base_url ?? "адрес не указан"}</span>
          </>
        ) : (
          <span>Загружаем прогон…</span>
        )}
      </div>
    </div>
  </div>
);
