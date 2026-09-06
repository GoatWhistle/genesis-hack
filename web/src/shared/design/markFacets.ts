export type MarkTone =
  | "providerLit"
  | "providerMid"
  | "providerDeep"
  | "contractLit"
  | "contractMid"
  | "contractDeep"
  | "edge";

export interface MarkFacet {
  tone: MarkTone;
  d: string;
}

export const MARK_FACETS: ReadonlyArray<MarkFacet> = [
  { tone: "contractLit", d: "M97.078 83.214L28.34 124.031l89.003-6.04 6.855-89.745z" },
  { tone: "contractDeep", d: "M117.488 117.93l-7.649-52.799-20.837 27.514z" },
  { tone: "contractDeep", d: "M117.592 117.93l-56.044-4.399-32.91 10.385z" },
  { tone: "providerDeep", d: "M28.717 123.928l14.001-45.867-30.81 6.588z" },
  { tone: "edge", d: "M88.996 92.797l-12.882-50.46-36.866 34.558z" },
  { tone: "contractLit", d: "M121.275 43.047L86.426 14.585l-9.704 31.373z" },
  { tone: "contractLit", d: "M104.978 4.437L84.481 15.764 71.551 4.285z" },
  { tone: "providerDeep", d: "M3.802 100.034l8.586-15.659L5.442 65.72z" },
  {
    tone: "providerMid",
    d: "M4.981 65.131l6.987 19.821 30.365-6.812L77 45.922l9.783-31.075L71.38 3.969l-26.19 9.802c-8.252 7.675-24.263 22.86-24.84 23.146-.573.291-10.575 19.195-15.369 28.214z"
  },
  {
    tone: "providerLit",
    d: "M29.519 29.521c17.882-17.73 40.937-28.207 49.785-19.28 8.843 8.926-.534 30.62-18.418 48.345-17.884 17.725-40.653 28.779-49.493 19.852-8.849-8.92.242-31.191 18.126-48.917z"
  },
  { tone: "providerMid", d: "M28.717 123.909l13.89-46.012 46.135 14.82c-16.68 15.642-35.233 28.865-60.025 31.192z" },
  { tone: "contractDeep", d: "M77.062 45.831l11.844 46.911c13.934-14.65 26.439-30.401 32.563-49.883l-44.407 2.972z" },
  { tone: "contractLit", d: "M121.348 43.097c4.74-14.305 5.833-34.825-16.517-38.635l-18.339 10.13 34.856 28.505z" },
  { tone: "providerMid", d: "M3.802 99.828c.656 23.608 17.689 23.959 24.945 24.167l-16.759-39.14-8.186 14.973z" },
  { tone: "contractMid", d: "M77.128 45.904c10.708 6.581 32.286 19.798 32.723 20.041.68.383 9.304-14.542 11.261-22.976l-43.984 2.935z" },
  { tone: "edge", d: "M42.589 77.897l18.57 35.828c10.98-5.955 19.579-13.211 27.454-20.983L42.589 77.897z" },
  { tone: "providerDeep", d: "M11.914 84.904l-2.631 31.331c4.964 6.781 11.794 7.371 18.96 6.842-5.184-12.9-15.538-38.696-16.329-38.173z" },
  { tone: "contractLit", d: "M86.384 14.67l36.891 5.177c-1.969-8.343-8.015-13.727-18.32-15.41L86.384 14.67z" }
];

export const MARK_FILL: Record<MarkTone, string> = {
  providerLit: "var(--facet-provider-lit)",
  providerMid: "var(--facet-provider-mid)",
  providerDeep: "var(--facet-provider-deep)",
  contractLit: "var(--facet-contract-lit)",
  contractMid: "var(--facet-contract-mid)",
  contractDeep: "var(--facet-contract-deep)",
  edge: "var(--facet-edge)"
};

export const MARK_SIDE: Record<MarkTone, "left" | "right" | "mid"> = {
  providerLit: "left",
  providerMid: "left",
  providerDeep: "left",
  contractLit: "right",
  contractMid: "right",
  contractDeep: "right",
  edge: "mid"
};
