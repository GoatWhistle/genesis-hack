import { LayoutGroup, motion } from "motion/react";
import { useSwapTransition } from "~/shared/lib/motion";
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
  group,
  role = "tablist",
  mono = true
}: SwitchTabsProps) => {
  const transition = useSwapTransition();
  const tab = role === "tablist";

  return (
    <div className="switch switch-sliding" role={role} aria-label={label}>
      <LayoutGroup id={`switch-${group}`}>
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
            onClick={() => onPick(option.id)}
          >
            {active ? (
              <motion.span
                layoutId={`switch-${group}`}
                className="switch-slider"
                transition={transition}
                aria-hidden="true"
              />
            ) : null}
            <span className="switch-text">{option.label}</span>
          </button>
        );
      })}
      </LayoutGroup>
    </div>
  );
};
