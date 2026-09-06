import { SwitchTabs } from "~/shared/ui/SwitchTabs";
import type { LabSource } from "../model/liveSource";

interface LabSourcePickProps {
  source: LabSource;
  onPick: (value: LabSource) => void;
}

const OPTIONS: { id: LabSource; title: string; hint: string }[] = [
  { id: "baked", title: "запечённый прогон", hint: "восемь готовых разборов: четыре описания в двух контрактах" },
  { id: "live", title: "своё описание", hint: "разберёт живой сервис" }
];

export const LabSourcePick = ({ source, onPick }: LabSourcePickProps) => (
  <div className="lab-source-pick">
    <span className="label">Что разбираем</span>
    <SwitchTabs
      label="Источник описания"
      group="lab-source"
      role="group"
      mono={false}
      options={OPTIONS.map((option) => ({ id: option.id, label: option.title, title: option.hint }))}
      current={source}
      onPick={(id) => onPick(id as LabSource)}
    />
  </div>
);
