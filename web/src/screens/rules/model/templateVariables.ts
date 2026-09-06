export const templateVariables = (source: string, known: string[]): string[] =>
  known.filter((name) => new RegExp(String.raw`<%[^%]*\b${name}\b`).test(source));
