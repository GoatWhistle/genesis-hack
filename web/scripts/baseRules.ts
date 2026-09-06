// Разбор base.yml на этапе сборки: страница «Начало» сопоставляет архетипы, но
// парсер YAML и шаблоны ERB ей для этого не нужны — в бандл уходит готовый JSON.
import { readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { parse } from "yaml";
import type { Plugin } from "vite";

const RULES = join(dirname(fileURLToPath(import.meta.url)), "..", "src", "data", "runs", "rules.json");


interface RawRule {
  field?: string;
  pattern?: string;
  weight?: number;
}

interface RawArchetype {
  rules?: RawRule[];
  veto?: RawRule[];
}

interface RawBase {
  archetypes?: Record<string, RawArchetype>;
  status_patterns?: Record<string, string[]>;
  error_semantics?: Record<string, string>;
  payload_patterns?: RawGroup[];
  requisite_patterns?: RawGroup[];
  path_patterns?: RawGroup[];
  callback_fields?: Record<string, string[]>;
  headers?: Record<string, string[]>;
  amount_units?: { minor_patterns?: string[]; multiplier?: number; minor_requires_integer?: boolean };
  amount_text_rules?: { kind?: string; comparison?: string; pattern?: string }[];
}

interface RawGroup {
  field?: string;
  patterns?: string[];
}

interface FieldGroup {
  field: string;
  patterns: string[];
}

const groups = (raw: RawGroup[] | undefined): FieldGroup[] => (raw ?? []).map((item) => ({ field: item.field ?? "", patterns: item.patterns ?? [] }));

const fromMap = (raw: Record<string, string[]> | undefined): FieldGroup[] => Object.entries(raw ?? {}).map(([field, patterns]) => ({ field, patterns }));

export const readBaseRules = async () => {
  const files = JSON.parse(await readFile(RULES, "utf8")) as Record<string, { content?: string }>;
  const raw = (parse(files["base.yml"]?.content ?? "") ?? {}) as RawBase;

  return {
    archetypes: Object.entries(raw.archetypes ?? {}).map(([name, body]) => ({
      name,
      rules: (body.rules ?? []).map((rule) => ({
        field: rule.field ?? "",
        pattern: rule.pattern ?? "",
        weight: rule.weight ?? 0
      })),
      veto: (body.veto ?? []).map((rule) => ({ field: rule.field ?? "", pattern: rule.pattern ?? "" }))
    })),
    statusPatterns: Object.entries(raw.status_patterns ?? {}).map(([group, patterns]) => ({ group, patterns })),
    errorSemantics: Object.entries(raw.error_semantics ?? {}).map(([code, meaning]) => ({ code, meaning })),
    payloadPatterns: groups(raw.payload_patterns),
    requisitePatterns: groups(raw.requisite_patterns),
    pathPatterns: groups(raw.path_patterns),
    callbackFields: fromMap(raw.callback_fields),
    headers: fromMap(raw.headers),
    amountUnits: {
      minorPatterns: raw.amount_units?.minor_patterns ?? [],
      multiplier: raw.amount_units?.multiplier ?? 100,
      minorRequiresInteger: raw.amount_units?.minor_requires_integer ?? false
    },
    amountTextRules: (raw.amount_text_rules ?? []).map((rule) => ({
      kind: rule.kind ?? "",
      comparison: rule.comparison ?? "",
      pattern: rule.pattern ?? ""
    }))
  };
};

export const baseRulesPlugin = (): Plugin => {
  const id = "virtual:base-rules";
  const resolved = `\0${id}`;

  return {
    name: "rsocket-base-rules",
    resolveId: (source: string) => (source === id ? resolved : undefined),
    load: async (source: string) =>
      source === resolved ? `export const baseRulesData = ${JSON.stringify(await readBaseRules())};` : undefined
  };
};

const SLIM_LANGS: Record<string, string> = {
  "virtual:lang-ruby": "ruby",
  "virtual:lang-erb": "erb",
  "virtual:lang-html": "html",
  "virtual:lang-yaml": "yaml",
  "virtual:lang-json": "json",
  "virtual:lang-markdown": "markdown"
};

const KEPT_EMBEDS: Record<string, string[]> = {
  "virtual:lang-ruby": [],
  "virtual:lang-erb": ["html", "ruby"],
  "virtual:lang-html": [],
  "virtual:lang-yaml": [],
  "virtual:lang-json": [],
  "virtual:lang-markdown": []
};

export const slimLangsPlugin = (): Plugin => {
  const resolved = (id: string) => `\0${id}`;

  return {
    name: "rsocket-slim-langs",
    resolveId: (source: string) => (SLIM_LANGS[source] ? resolved(source) : undefined),
    load: async (source: string) => {
      const id = Object.keys(SLIM_LANGS).find((key) => resolved(key) === source);
      if (!id) return undefined;
      const entry = createRequire(import.meta.url).resolve(`@shikijs/langs/${SLIM_LANGS[id]}`);
      const file = entry.replace(/\.d\.mts$/, ".mjs");
      const body = await readFile(file, "utf8");
      const literal = body.match(/JSON\.parse\((".*")\)/s)?.[1];
      if (!literal) throw new Error(`не разобран грамматический модуль ${SLIM_LANGS[id]}`);
      const grammar = JSON.parse(JSON.parse(literal) as string) as Record<string, unknown>;
      const kept = KEPT_EMBEDS[id] ?? [];
      grammar.embeddedLangs = kept;
      return `export default [${JSON.stringify(grammar)}];`;
    }
  };
};
