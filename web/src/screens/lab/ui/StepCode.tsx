import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { langOf, useHighlight } from "~/shared/lib/useHighlight";
import { enterVariants, useSwapTransition } from "~/shared/lib/motion";
import { DownloadRun } from "~/shared/ui/DownloadRun";
import { CodeFrame } from "~/shared/ui/CodeFrame";
import { CopyIcon } from "~/shared/design/CopyIcon";
import { SwitchTabs } from "~/shared/ui/SwitchTabs";
import { TracedCode } from "./TracedCode";
import { useProvenanceLink } from "./useProvenance";

interface PlainProps {
  file: string;
  code: string;
  actions?: React.ReactNode;
}

const PlainCode = ({ file, code, actions }: PlainProps) => {
  const lang = langOf(file);
  const html = useHighlight(code, lang);

  return (
    <CodeFrame name={file} lang={lang} code={code} actions={actions}>
      <div className="code-frame-body scroll-x">
        {html ? (
          <div dangerouslySetInnerHTML={{ __html: html }} />
        ) : (
          <pre>
            <code>{code}</code>
          </pre>
        )}
      </div>
    </CodeFrame>
  );
};

const CopyButton = ({ code }: { code: string }) => {
  const [done, setDone] = useState(false);

  useEffect(() => {
    if (!done) return;
    const timer = window.setTimeout(() => setDone(false), 1600);
    return () => window.clearTimeout(timer);
  }, [done]);

  return (
    <button
      type="button"
      className="btn btn-ghost btn-icon lab-code-btn"
      aria-label={done ? "Скопировано" : "Скопировать код"}
      title={done ? "Скопировано" : "Скопировать код"}
      onClick={() => {
        void navigator.clipboard.writeText(code).then(() => setDone(true));
      }}
    >
      <CopyIcon size={18} done={done} />
    </button>
  );
};

const Honesty = () => {
  const { map } = useProvenanceLink();
  if (map.total === 0) return null;
  const share = Math.round((map.explained / map.total) * 100);

  return (
    <p className="lab-honesty">
      <span className="lab-honesty-count mono">{share}%</span>
      <span className="lab-honesty-bar" aria-hidden="true">
        <motion.span
          initial={{ scaleX: 0 }}
          animate={{ scaleX: share / 100 }}
          transition={{ duration: 0.5, ease: [0.25, 1, 0.5, 1] }}
        />
      </span>
      <span>
        строк кода возводится к конкретному решению инструмента. Остальное — общий каркас запросов
        и разбора ответа, он одинаков у всех провайдеров.
      </span>
    </p>
  );
};

interface StepCodeProps {
  files: Record<string, string>;
  contract: string;
  provider: string;
  traced: string;
}

export const StepCode = ({ files, contract, provider, traced }: StepCodeProps) => {
  const names = Object.keys(files);
  const [picked, setPicked] = useState(names[0]);
  const active = picked && names.includes(picked) ? picked : names[0];
  const code = (active ? files[active] : undefined) ?? "";
  const swap = useSwapTransition();

  const actions = (
    <>
      {code ? <CopyButton code={code} /> : null}
      <DownloadRun files={files} provider={provider} contract={contract} />
    </>
  );

  return (
    <>
      <p className="prose-column">
        Файлы собраны по шаблонам контракта <span className="side-contract">{contract}</span>. Роли из
        шага 2 стали методами, словарь из шага 3 — константой{" "}
        <code className="mono">STATUS_MAP</code>, ограничения из шага 4 — предпроверками. Строки с
        чертой слева помнят своё решение — наведите на любую.
      </p>

      {active === traced ? <Honesty /> : null}

      <div className="lab-code-tabs">
        <SwitchTabs
          label="Файлы прогона"
          group="lab-files"
          options={names.map((name) => ({ id: name, label: name }))}
          current={active ?? ""}
          onPick={setPicked}
        />
      </div>

      <AnimatePresence mode="wait" initial={false}>
        <motion.div
          key={`${contract}:${active}`}
          variants={enterVariants}
          initial="hidden"
          animate="shown"
          exit="gone"
          transition={swap}
        >
          {active === traced ? (
            <TracedCode code={code} lang={langOf(active)} name={active} actions={actions} />
          ) : active ? (
            <PlainCode file={active} code={code} actions={actions} />
          ) : null}
        </motion.div>
      </AnimatePresence>
    </>
  );
};
