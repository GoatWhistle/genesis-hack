import js from "@eslint/js";
import ts from "typescript-eslint";
import hooks from "eslint-plugin-react-hooks";
import globals from "globals";

const SCREENS = ["home", "lab", "rules", "providers", "docs"];

const foreignScreens = (screen) =>
  SCREENS.filter((other) => other !== screen).flatMap((other) => [
    `~/screens/${other}/*`,
    `~/screens/${other}/**`
  ]);

const screenIsolation = SCREENS.map((screen) => ({
  files: [`src/screens/${screen}/**/*.{ts,tsx}`],
  rules: {
    "no-restricted-imports": [
      "error",
      {
        patterns: [
          {
            group: foreignScreens(screen),
            message: "Экран не импортирует из чужого экрана — общее поднимите в src/shared."
          }
        ]
      }
    ]
  }
}));

const sharedIsolation = {
  files: ["src/shared/**/*.{ts,tsx}"],
  rules: {
    "no-restricted-imports": [
      "error",
      {
        patterns: [
          {
            group: ["~/screens/*", "~/screens/**", "~/layout/*", "~/layout/**"],
            message: "shared не зависит ни от экранов, ни от каркаса."
          }
        ]
      }
    ]
  }
};

export default ts.config(
  { ignores: ["dist", "node_modules", "src/shared/api/schema.d.ts"] },
  js.configs.recommended,
  ...ts.configs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: { globals: globals.browser },
    plugins: { "react-hooks": hooks },
    rules: {
      ...hooks.configs.recommended.rules,
      "max-lines": ["error", { max: 250, skipBlankLines: true, skipComments: true }],
      "no-inline-comments": "error",
      "no-warning-comments": ["error", { terms: ["todo", "fixme", "xxx"], location: "anywhere" }],
      "@typescript-eslint/ban-ts-comment": "error",
      "@typescript-eslint/consistent-type-imports": "error",
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }]
    }
  },
  ...screenIsolation,
  sharedIsolation,
  { files: ["scripts/**/*.mjs"], languageOptions: { globals: globals.node } }
);
