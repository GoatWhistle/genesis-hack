import type { ReactNode } from "react";
import "./codeframe.css";

const LANG_TITLE: Record<string, string> = {
  ruby: "Ruby",
  erb: "ERB",
  yaml: "YAML",
  json: "JSON",
  markdown: "Markdown",
  html: "HTML",
  text: "текст"
};

export const langTitle = (lang: string) => LANG_TITLE[lang] ?? lang;

export const countLines = (code: string) => (code ? code.split("\n").length : 0);

const sizeOf = (code: string) => {
  const bytes = new TextEncoder().encode(code).length;
  if (bytes < 1024) return `${bytes} Б`;
  return `${(bytes / 1024).toFixed(1).replace(".", ",")} КБ`;
};

interface CodeFrameProps {
  name: string;
  lang: string;
  code: string;
  side?: "provider" | "contract";
  actions?: ReactNode;
  children: ReactNode;
}

export const CodeFrame = ({ name, lang, code, side, actions, children }: CodeFrameProps) => (
  <figure className="code-frame" data-side={side}>
    <figcaption className="code-frame-head">
      <span className="code-frame-name mono">{name}</span>
      <span className="code-frame-meta">
        <span className="code-frame-lang">{langTitle(lang)}</span>
        <span className="code-frame-dot" aria-hidden="true" />
        <span className="code-frame-size mono">{countLines(code)} строк</span>
        <span className="code-frame-dot" aria-hidden="true" />
        <span className="code-frame-size mono">{sizeOf(code)}</span>
      </span>
      {actions ? <span className="code-frame-actions">{actions}</span> : null}
    </figcaption>
    {children}
  </figure>
);
