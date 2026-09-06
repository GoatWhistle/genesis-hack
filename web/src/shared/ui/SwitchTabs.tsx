import { useState } from "react";
import { SlidingPlate } from "./SlidingPlate";
import "./switchtabs.css";

export interface SwitchOption {
  id: string;
  label: string;
  title?: string;
}

interface SwitchTabsProps {
  label: string;
  options: readonly SwitchOption[];
  current: string;
  onPick: (id: string) => void;
  group: string;
  role?: "tablist" | "group";
  mono?: boolean;
}

export const SwitchTabs = ({
  label,
  options,
  current,
  onPick,
  role = "tablist",
  mono = true
}: SwitchTabsProps) => {
  const [host, setHost] = useState<HTMLDivElement | null>(null);
  const tab = role === "tablist";

  return (
    <div className="switch switch-sliding" role={role} aria-label={label} ref={setHost}>
      <SlidingPlate host={host} activeKey={current} className="switch-slider" />
      {options.map((option) => {
        const active = option.id === current;

        return (
          <button
            key={option.id}
            type="button"
            role={tab ? "tab" : undefined}
            className={mono ? "switch-item mono" : "switch-item"}
            aria-selected={tab ? active : undefined}
            aria-pressed={tab ? undefined : active}
            title={option.title}
            data-active={active}
            data-plate={active}
            onClick={() => onPick(option.id)}
          >
            <span className="switch-text">{option.label}</span>
          </button>
        );
      })}
    </div>
  );
};
