import { AnimatePresence, motion } from "motion/react";
import type { PageProps } from "~/layout/types";
import { useSearchParam } from "~/layout/useRoute";
import { SideNav } from "~/shared/ui/SideNav";
import { enterVariants, useSwapTransition } from "~/shared/lib/motion";
import { Archetypes, Check, ContractUpload, Contracts, Dictionaries, Playground } from "./sections";
import "./rules.css";

const SECTIONS = [
  { id: "check", title: "Проверить правило" },
  { id: "archetypes", title: "Архетипы операций" },
  { id: "dictionaries", title: "Словари распознавания" },
  { id: "contracts", title: "Профили контрактов" },
  { id: "upload", title: "Загрузить контракт" },
  { id: "sandbox", title: "Песочница" }
] as const;

type SectionId = (typeof SECTIONS)[number]["id"];

const isSection = (value: string): value is SectionId =>
  SECTIONS.some((section) => section.id === value);

const BODIES: Record<SectionId, React.ComponentType<PageProps>> = {
  check: Check,
  archetypes: Archetypes,
  dictionaries: Dictionaries,
  contracts: Contracts,
  upload: ContractUpload,
  sandbox: Playground
};

const Rules = ({ go }: PageProps) => {
  const [raw, setSection] = useSearchParam("r", "check", isSection);
  const current: SectionId = isSection(raw) ? raw : "check";
  const Body = BODIES[current];
  const swap = useSwapTransition();

  return (
    <div className="shell-wide band rls">
      <header className="rls-head">
        <h1>Решение живёт в правилах</h1>
        <p className="prose-column">
          Настоящий <code className="mono">base.yml</code> инструмента, разобранный по смыслу. В нём
          нет ни одного имени метода заказчика и ни строчки Ruby: только то, как провайдеры называют
          операции, поля и состояния. Новый вариант написания{" "}
          <code className="mono side-provider">operationId</code> добавляется правкой одной строки —
          сразу для всех контрактов.
        </p>
      </header>

      <div className="side-grid">
        <SideNav label="Разделы правил" items={SECTIONS} current={current} onPick={setSection} />

        <section className="rls-body" aria-live="polite">
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={current}
              variants={enterVariants}
              initial="hidden"
              animate="shown"
              exit="gone"
              transition={swap}
            >
              <h2 className="rls-h2">{SECTIONS.find((section) => section.id === current)?.title}</h2>
              <Body go={go} />
            </motion.div>
          </AnimatePresence>
        </section>
      </div>
    </div>
  );
};

export default Rules;
