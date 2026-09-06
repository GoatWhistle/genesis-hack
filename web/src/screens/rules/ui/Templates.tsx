import { useMemo, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { ruleFile, ruleKeys } from "~/shared/api/rules";
import { langOf, useHighlight } from "~/shared/lib/useHighlight";
import { enterVariants, useSwapTransition } from "~/shared/lib/motion";
import { CodeFrame } from "~/shared/ui/CodeFrame";
import { SwitchTabs } from "~/shared/ui/SwitchTabs";
import { templateVariables } from "../model/templateVariables";

const VARIABLE_NOTES: Record<string, string> = {
  provider: "имя провайдера из описания",
  contract: "имя контракта заказчика",
  class_name: "имя класса, собранное из имени провайдера",
  base_url: "адрес из servers описания",
  http: "таймауты и user-agent из contract.yml",
  status_entries: "статусы провайдера, переведённые в статусы контракта",
  event_map: "события webhook в терминах контракта",
  error_entries: "HTTP-коды провайдера → коды ошибок контракта",
  roles: "роли контракта с привязанными операциями",
  env_prefix: "префикс переменных окружения",
  conditions: "ограничения суммы и валюты из описания",
  amount: "выражение приведения суммы",
  callback: "разбор тела уведомления",
  auth: "как подписывается запрос",
  amount_expression: "выражение приведения суммы из contract.yml",
  constraint_checks: "проверки границ суммы и валюты",
  constraint_constants: "константы границ, взятые из описания",
  error_codes_for: "коды ошибок контракта по смыслу из base.yml",
  payload_literal: "тело запроса, собранное из узнанных полей",
  path_literal: "путь с подставленными параметрами",
  request_for: "метод и адрес операции провайдера",
  binding_for: "решение по роли: операция, счёт, правила",
  credentials: "схема авторизации из описания провайдера"
};

const KNOWN = Object.keys(VARIABLE_NOTES);

const templateKeys = ruleKeys.filter((key) => key.endsWith(".erb"));

const shortName = (key: string) => key.replace(/^contracts\//, "");

export const Templates = () => {
  const [open, setOpen] = useState(templateKeys[0] ?? "");
  const source = ruleFile(open)?.content ?? "";
  const html = useHighlight(source, langOf(open));
  const variables = useMemo(() => templateVariables(source, KNOWN), [source]);
  const swap = useSwapTransition();

  return (
    <div className="tpl">
      <div className="scroll-x tpl-tabs-wrap">
        <SwitchTabs
          label="Шаблон"
          group="rules-templates"
          options={templateKeys.map((key) => ({ id: key, label: shortName(key) }))}
          current={open}
          onPick={setOpen}
        />
      </div>

      <div className="tpl-body">
        <div className="tpl-vars">
          <h3 className="label tpl-vars-title">что шаблон берёт из разбора</h3>
          <ul className="tpl-var-list">
            {variables.map((name) => (
              <li key={name} className="tpl-var">
                <code className="mono side-contract">{name}</code>
                {VARIABLE_NOTES[name] ? (
                  <span className="tpl-var-note">{VARIABLE_NOTES[name]}</span>
                ) : null}
              </li>
            ))}
          </ul>
        </div>

        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={open}
            variants={enterVariants}
            initial="hidden"
            animate="shown"
            exit="gone"
            transition={swap}
          >
            <CodeFrame name={shortName(open)} lang={langOf(open)} code={source} side="contract">
              <div className="code-frame-body tpl-code scroll-x">
                {html ? (
                  <div dangerouslySetInnerHTML={{ __html: html }} />
                ) : (
                  <pre>
                    <code>{source}</code>
                  </pre>
                )}
              </div>
            </CodeFrame>
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
};
