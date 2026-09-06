import type { ThemeRegistrationRaw } from "shiki/core";

const INK = "#0e0f12";
const INK_SOFT = "#4b4d52";
const INK_FAINT = "#64666b";
const PROVIDER = "#c12b11";
const PROVIDER_DEEP = "#9c1c10";
const CONTRACT = "#2751b8";
const CONTRACT_DEEP = "#1a3b8b";
const SURFACE = "#f7f8f9";

export const codeThemeName = "rsocket-light";

export const codeTheme: ThemeRegistrationRaw = {
  name: codeThemeName,
  type: "light",
  colors: {
    "editor.background": SURFACE,
    "editor.foreground": INK
  },
  settings: [
    {
      settings: { background: SURFACE, foreground: INK }
    },
    {
      scope: ["comment", "punctuation.definition.comment", "string.comment"],
      settings: { foreground: INK_FAINT, fontStyle: "italic" }
    },
    {
      scope: [
        "keyword",
        "keyword.control",
        "keyword.operator.expression",
        "keyword.other",
        "storage",
        "storage.type",
        "storage.modifier",
        "variable.language",
        "keyword.control.class",
        "keyword.control.def",
        "keyword.control.module",
        "meta.embedded keyword"
      ],
      settings: { foreground: CONTRACT, fontStyle: "" }
    },
    {
      scope: [
        "entity.name.function",
        "support.function",
        "meta.function-call",
        "meta.function-call.generic",
        "entity.name.function.method",
        "variable.function"
      ],
      settings: { foreground: CONTRACT_DEEP }
    },
    {
      scope: [
        "entity.name.type",
        "entity.name.class",
        "entity.name.namespace",
        "entity.other.inherited-class",
        "support.class",
        "support.type",
        "entity.name.tag.yaml",
        "variable.other.constant"
      ],
      settings: { foreground: CONTRACT_DEEP, fontStyle: "" }
    },
    {
      scope: [
        "string",
        "string.quoted",
        "string.quoted.single",
        "string.quoted.double",
        "string.unquoted",
        "string.other",
        "punctuation.definition.string",
        "string.regexp",
        "meta.embedded.line.ruby string"
      ],
      settings: { foreground: PROVIDER }
    },
    {
      scope: [
        "constant.character.escape",
        "punctuation.section.embedded",
        "punctuation.definition.template-expression",
        "meta.embedded.line.ruby punctuation.section.embedded"
      ],
      settings: { foreground: PROVIDER_DEEP }
    },
    {
      scope: [
        "constant.numeric",
        "constant.numeric.integer",
        "constant.numeric.float",
        "constant.other.symbol",
        "constant.language.symbol"
      ],
      settings: { foreground: INK }
    },
    {
      scope: [
        "constant.language",
        "constant.language.boolean",
        "constant.language.null",
        "constant.other"
      ],
      settings: { foreground: CONTRACT_DEEP }
    },
    {
      scope: [
        "variable",
        "variable.other",
        "variable.parameter",
        "variable.other.readwrite",
        "meta.definition.variable"
      ],
      settings: { foreground: INK }
    },
    {
      scope: ["variable.other.instance", "variable.other.global", "variable.other.class"],
      settings: { foreground: INK_SOFT }
    },
    {
      scope: [
        "punctuation",
        "meta.brace",
        "punctuation.separator",
        "punctuation.terminator",
        "punctuation.definition.parameters",
        "keyword.operator"
      ],
      settings: { foreground: INK_SOFT }
    },
    {
      scope: [
        "support.type.property-name.json",
        "string.json support.type.property-name",
        "meta.structure.dictionary.key"
      ],
      settings: { foreground: CONTRACT_DEEP }
    },
    {
      scope: ["entity.name.tag", "meta.tag", "punctuation.definition.tag"],
      settings: { foreground: CONTRACT }
    },
    {
      scope: ["entity.other.attribute-name"],
      settings: { foreground: PROVIDER_DEEP }
    },
    {
      scope: ["markup.heading", "entity.name.section.markdown", "markup.heading.markdown"],
      settings: { foreground: CONTRACT_DEEP, fontStyle: "bold" }
    },
    {
      scope: ["markup.bold"],
      settings: { foreground: INK, fontStyle: "bold" }
    },
    {
      scope: ["markup.italic"],
      settings: { foreground: INK, fontStyle: "italic" }
    },
    {
      scope: ["markup.inline.raw", "markup.raw", "markup.fenced_code", "markup.raw.block"],
      settings: { foreground: PROVIDER }
    },
    {
      scope: ["markup.underline.link", "string.other.link", "markup.link"],
      settings: { foreground: CONTRACT, fontStyle: "underline" }
    },
    {
      scope: ["markup.list"],
      settings: { foreground: INK }
    },
    {
      scope: ["beginning.punctuation.definition.list", "punctuation.definition.list"],
      settings: { foreground: INK_SOFT }
    },
    {
      scope: ["markup.quote"],
      settings: { foreground: INK_SOFT, fontStyle: "italic" }
    },
    {
      scope: ["invalid", "invalid.illegal"],
      settings: { foreground: PROVIDER_DEEP }
    }
  ]
};
