import { useEffect, useRef } from "react";
import { useTokens, type CodeToken } from "~/shared/lib/useHighlight";
import { CodeFrame } from "~/shared/ui/CodeFrame";
import { useProvenanceLink } from "./useProvenance";
import { ProvenanceNote } from "./ProvenanceNote";

interface TracedCodeProps {
  code: string;
  lang: string;
  name: string;
  actions?: React.ReactNode;
}

const Tokens = ({ tokens }: { tokens: CodeToken[] }) => (
  <>
    {tokens.map((token, index) => (
      <span key={index} style={{ color: token.color }}>
        {token.content}
      </span>
    ))}
  </>
);

const useScrollToLit = (lit: number | undefined) => {
  const box = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (lit === undefined) return;
    const host = box.current;
    const row = host?.querySelector<HTMLElement>(`[data-line="${lit}"]`);
    if (!host || !row) return;
    const above = row.offsetTop < host.scrollTop;
    const below = row.offsetTop + row.offsetHeight > host.scrollTop + host.clientHeight;
    if (above || below) host.scrollTo({ top: row.offsetTop - host.clientHeight / 3, behavior: "smooth" });
  }, [lit]);

  return box;
};

export const TracedCode = ({ code, lang, name, actions }: TracedCodeProps) => {
  const lines = useTokens(code, lang);
  const { map, active, setActive } = useProvenanceLink();
  const litLines = active ? map.linesBySource.get(active) : undefined;
  const box = useScrollToLit(litLines?.[0]);
  const source = active ? map.sources.get(active) : undefined;

  if (!lines) {
    return (
      <div className="lab-traced">
        <CodeFrame name={name} lang={lang} code={code} side="contract" actions={actions}>
          <div className="code-frame-body scroll-x">
            <pre>
              <code>{code}</code>
            </pre>
          </div>
        </CodeFrame>
      </div>
    );
  }

  const litSet = new Set(litLines);

  return (
    <div className="lab-traced">
      <CodeFrame name={name} lang={lang} code={code} side="contract" actions={actions}>
        <div className="code-frame-body lab-code-traced" ref={box}>
          <div className="code-rows" role="list">
            {lines.map((tokens, index) => {
              const id = map.sourceByLine.get(index);
              const traced = id !== undefined;
              const lit = litSet.has(index);
              const side = id ? map.sources.get(id)?.side : undefined;

              return (
                <div
                  key={index}
                  role="listitem"
                  data-line={index}
                  className={[
                    "code-row",
                    "lab-line",
                    traced ? "lab-line-traced" : "",
                    lit ? "lab-line-lit" : "",
                    side ? `lab-line-${side}` : ""
                  ]
                    .filter(Boolean)
                    .join(" ")}
                  tabIndex={traced ? 0 : -1}
                  aria-label={traced ? `строка ${index + 1}, ${map.sources.get(id)?.title}` : undefined}
                  onMouseEnter={() => traced && setActive(id)}
                  onMouseLeave={() => traced && setActive(undefined)}
                  onFocus={() => traced && setActive(id)}
                  onBlur={() => traced && setActive(undefined)}
                >
                  <span className="code-row-no" aria-hidden="true">
                    {index + 1}
                  </span>
                  <code className="code-row-text">
                    <Tokens tokens={tokens} />
                  </code>
                </div>
              );
            })}
          </div>
        </div>
      </CodeFrame>

      <ProvenanceNote source={source} count={litLines?.length ?? 0} />
    </div>
  );
};
