import { useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { PageProps } from "~/layout/types";
import { useSearchParam } from "~/layout/useRoute";
import { TAKES } from "../model/cli";
import { Terminal } from "~/shared/ui/Terminal";
import { ENDPOINTS, NOT_FOUND } from "../model/endpoints";
import { EndpointCard } from "./EndpointCard";
import { Storage } from "./Storage";
import { AddContract, AddRule } from "./HowTo";
import { Decisions } from "./Decisions";
import { SideNav } from "~/shared/ui/SideNav";
import { SwitchTabs } from "~/shared/ui/SwitchTabs";
import { enterVariants, useSwapTransition } from "~/shared/lib/motion";
import "./docs.css";

const SECTIONS = [
  { id: "cli", title: "Командная строка" },
  { id: "http", title: "HTTP API" },
  { id: "storage", title: "Хранилища" },
  { id: "contract", title: "Как добавить контракт" },
  { id: "rule", title: "Как добавить правило" },
  { id: "decisions", title: "Решения, которые чаще всего спрашивают" }
] as const;

type SectionId = (typeof SECTIONS)[number]["id"];

const isSection = (value: string): value is SectionId =>
  SECTIONS.some((section) => section.id === value);

const Cli = () => {
  const [openTake, setOpenTake] = useState(TAKES[0]?.id ?? "");
  const take = TAKES.find((item) => item.id === openTake) ?? TAKES[0];

  return (
    <>
      <p className="prose-column doc-lead">
        Одна и та же сборка доступна из командной строки и по HTTP — обе идут в один менеджер
        сборок, поэтому <code className="mono">bin/rsocket build</code> и{" "}
        <code className="mono">POST /build</code> на одном описании дают одинаковые файлы. Ниже
        дословный вывод команд: его можно повторить.
      </p>

      <div className="scroll-x doc-bar">
        <SwitchTabs
          label="Команда"
          group="docs-cli"
          options={TAKES.map((item) => ({ id: item.id, label: item.id }))}
          current={openTake}
          onPick={setOpenTake}
        />
      </div>

      {take ? <Terminal key={take.id} take={take} /> : null}
    </>
  );
};

const Http = () => (
  <>
    <p className="prose-column doc-lead">
      Сервер ничего не решает сам: разбирает запрос, зовёт менеджер сборок и печатает результат
      JSON-ом. Состояния он не хранит — каждый запрос отдельная сборка, файлы уходят в ответе.
      Аутентификации нет: инструмент рассчитан на запуск внутри контура разработки. У безопасных
      ручек есть кнопка «выполнить» — она бьёт в настоящий сервис.
    </p>

    <div className="eps">
      {ENDPOINTS.map((endpoint) => (
        <EndpointCard key={endpoint.id} endpoint={endpoint} />
      ))}
    </div>

    <div className="doc-aside">
      <h3 className="doc-h3">Об ошибках</h3>
      <p className="prose-column">
        Ответ об ошибке всегда JSON с полем <code className="mono">error</code>. Разница между 400
        и 422 намеренная: <strong>400</strong> — запрос сформулирован неверно,{" "}
        <strong>422</strong> — запрос понят, но описание провайдера не годится для сборки. Во
        втором случае текст называет роли, которых не хватило, и говорит, где лежат правила.
        Несуществующая ручка отвечает списком существующих:
      </p>
      <pre className="ep-code scroll-x" tabIndex={0}>
        <code>{NOT_FOUND}</code>
      </pre>
      <p className="prose-column doc-note">
        Кириллица в строке запроса (<code className="mono">?contract=профиль</code>) должна быть
        percent-encoded — иначе WEBrick отклонит запрос как некорректный URI ещё до нашего кода.
      </p>
    </div>
  </>
);

const BODIES: Record<SectionId, () => React.ReactElement> = {
  cli: Cli,
  http: Http,
  storage: Storage,
  contract: AddContract,
  rule: AddRule,
  decisions: Decisions
};

const Docs = (_props: PageProps) => {
  const [raw, setSection] = useSearchParam("r", "cli", isSection);
  const current: SectionId = isSection(raw) ? raw : "cli";
  const Body = BODIES[current];
  const swap = useSwapTransition();

  return (
    <div className="shell-wide band doc">
      <header className="doc-head">
        <h1>Документация</h1>
        <p className="prose-column">
          Инструмент читает описание OpenAPI и собирает по нему заготовку интеграции. Здесь — как
          его запустить, чем спросить и как расширить, не трогая ни строчки его кода.
        </p>
      </header>

      <div className="side-grid">
        <SideNav
          label="Разделы документации"
          items={SECTIONS}
          current={current}
          onPick={setSection}
        />

        <section className="doc-body" aria-live="polite">
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={current}
              variants={enterVariants}
              initial="hidden"
              animate="shown"
              exit="gone"
              transition={swap}
            >
              <h2 className="doc-h2">{SECTIONS.find((section) => section.id === current)?.title}</h2>
              <Body />
            </motion.div>
          </AnimatePresence>
        </section>
      </div>
    </div>
  );
};

export default Docs;
