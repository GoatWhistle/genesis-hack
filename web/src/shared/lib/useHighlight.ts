import { useEffect, useState } from "react";
import { createHighlighterCore } from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import { codeTheme, codeThemeName } from "~/shared/design/codeTheme";

const LANGS: Record<string, string> = {
  rb: "ruby",
  erb: "erb",
  html: "html",
  yml: "yaml",
  yaml: "yaml",
  json: "json",
  md: "markdown"
};

export const langOf = (file: string) => {
  const parts = file.split(".");
  const last = parts.pop() ?? "";
  if (last === "erb") return LANGS[parts.pop() ?? ""] ?? "erb";
  return LANGS[last] ?? "text";
};

const LANG_SOURCE: Record<string, () => Promise<unknown>> = {
  ruby: () => import("virtual:lang-ruby"),
  erb: () => import("virtual:lang-erb"),
  html: () => import("virtual:lang-html"),
  yaml: () => import("virtual:lang-yaml"),
  json: () => import("virtual:lang-json"),
  markdown: () => import("virtual:lang-markdown")
};

let highlighter: ReturnType<typeof createHighlighterCore> | undefined;

const loaded = new Set<string>();

const shiki = async (lang: string) => {
  highlighter ??= createHighlighterCore({
    themes: [codeTheme],
    langs: [],
    engine: createJavaScriptRegexEngine()
  });

  const core = await highlighter;
  const source = LANG_SOURCE[lang];

  if (source && !loaded.has(lang)) {
    loaded.add(lang);
    await core.loadLanguage((await source()) as never);
  }

  return core;
};

export interface CodeToken {
  content: string;
  color?: string;
}

export const useHighlight = (code: string, lang: string) => {
  const [done, setDone] = useState<{ code: string; html: string }>();

  useEffect(() => {
    let alive = true;

    shiki(lang)
      .then((core) => core.codeToHtml(code, { lang, theme: codeThemeName }))
      .then((html) => alive && setDone({ code, html }))
      .catch(() => undefined);

    return () => {
      alive = false;
    };
  }, [code, lang]);

  return done?.code === code ? done.html : undefined;
};

export const useTokens = (code: string, lang: string) => {
  const [done, setDone] = useState<{ code: string; lines: CodeToken[][] }>();

  useEffect(() => {
    let alive = true;

    shiki(lang)
      .then((core) => core.codeToTokens(code, { lang, theme: codeThemeName }))
      .then((result) => {
        if (!alive) return;
        const lines = result.tokens.map((line) =>
          line.map((token) => ({ content: token.content, color: token.color }))
        );
        setDone({ code, lines });
      })
      .catch(() => undefined);

    return () => {
      alive = false;
    };
  }, [code, lang]);

  return done?.code === code ? done.lines : undefined;
};
