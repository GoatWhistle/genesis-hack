import type { BuildOutcome } from "~/shared/api/types";

export interface AmountShape {
  provider: string;
  field: string;
  type: string;
  units: string;
  multiplier: number;
  note: string;
}

const AMOUNT_WARNING = /^сумма провайдера:\s*(\S+)\s*\(([^)]+)\),\s*единицы:\s*(.+)$/;

export const amountShape = (run: BuildOutcome): AmountShape => {
  const line = run.report.warnings.find((text) => AMOUNT_WARNING.test(text));
  const parsed = line?.match(AMOUNT_WARNING);

  return {
    provider: run.provider,
    field: parsed?.[1] ?? "amount",
    type: parsed?.[2] ?? "number",
    units: parsed?.[3] ?? run.report.amount.note,
    multiplier: run.report.amount.multiplier,
    note: run.report.amount.note
  };
};

export const wireValue = (shape: AmountShape, rubles: number): string => {
  const scaled = rubles * shape.multiplier;

  if (shape.type === "integer") return String(Math.round(scaled));
  if (shape.type === "string") return `"${scaled.toFixed(2)}"`;
  return Number.isInteger(scaled) ? String(scaled) : scaled.toFixed(2);
};

export const rublesLabel = (rubles: number): string => `${rubles.toLocaleString("ru-RU")} ₽`;

export const confusionFactor = (shapes: AmountShape[]): number => {
  const multipliers = shapes.map((shape) => shape.multiplier);
  return Math.max(...multipliers) / Math.min(...multipliers);
};
