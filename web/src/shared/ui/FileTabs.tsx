import { useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { langOf, useHighlight } from "~/shared/lib/useHighlight";
import { enterVariants, useSwapTransition } from "~/shared/lib/motion";
import { Markdown } from "./Markdown";
import { CodeFrame } from "./CodeFrame";
import { SwitchTabs } from "./SwitchTabs";

const HIDDEN = "mapping.yml";

const isMarkdown = (name: string) => name.toLowerCase().endsWith(".md");

const Highlighted = ({ name, body }: { name: string; body: string }) => {
  const html = useHighlight(body, langOf(name));

  return (
    <div className="code-frame-body scroll-x">
      {html ? (
        <div dangerouslySetInnerHTML={{ __html: html }} />
      ) : (
        <pre>
          <code>{body}</code>
        </pre>
      )}
    </div>
  );
};

interface Props {
  files: Record<string, string>;
}

export const FileTabs = ({ files }: Props) => {
  const names = Object.keys(files).filter((name) => name !== HIDDEN);
  const [open, setOpen] = useState(names[0] ?? "");
  const current = names.includes(open) ? open : (names[0] ?? "");
  const body = files[current] ?? "";
  const swap = useSwapTransition();

  return (
    <div className="files">
      <div className="scroll-x files-bar">
        <SwitchTabs
          label="Файлы сборки"
          group="provider-files"
          options={names.map((name) => ({ id: name, label: name }))}
          current={current}
          onPick={setOpen}
        />
      </div>

      <AnimatePresence mode="wait" initial={false}>
        <motion.div
          key={current}
          variants={enterVariants}
          initial="hidden"
          animate="shown"
          exit="gone"
          transition={swap}
        >
          <CodeFrame name={current} lang={langOf(current)} code={body} side="contract">
            {isMarkdown(current) ? (
              <div className="code-frame-body files-md scroll-x">
                <Markdown source={body} />
              </div>
            ) : (
              <Highlighted name={current} body={body} />
            )}
          </CodeFrame>
        </motion.div>
      </AnimatePresence>
    </div>
  );
};
