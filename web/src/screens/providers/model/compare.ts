import type { BuildOutcome, Report } from "~/shared/api/types";
import { isBound } from "~/shared/api/types";

export interface Cell {
  text: string;
  side?: "provider" | "contract";
  note?: string;

  odd?: boolean;
}

export interface CompareRow {
  key: string;
  title: string;
  hint: string;
  cells: Record<string, Cell>;
}

const CREATE_ROLE = "create_request";

const amountCell = (report: Report): Cell => {

  const warning = report.warnings.find((line) => line.startsWith("сумма провайдера:"));
  const shape = warning?.replace("сумма провайдера: ", "") ?? report.amount.note;
  return {
    text: shape,
    side: "provider",
    note: report.amount.multiplier === 1 ? "×1" : `×${report.amount.multiplier}`,
    odd: shape.includes("string")
  };
};

const createCell = (report: Report): Cell => {
  const role = report.roles[CREATE_ROLE];
  if (!role || !isBound(role)) return { text: "не распознана", odd: true };
  return { text: role.operation, side: "provider", note: role.endpoint };
};

const authCell = (report: Report): Cell => {
  const { primary, alternatives } = report.auth;
  if (!primary) return { text: "нет securitySchemes", note: "дописать руками", odd: true };
  if (alternatives.length > 0)
    return {
      text: primary,
      side: "provider",
      note: `ещё ${alternatives.length}: ${alternatives.join(", ")}`,
      odd: true
    };
  return { text: primary, side: "provider" };
};

const statusCell = (report: Report): Cell => {
  const words = Object.keys(report.statuses);
  const capsed = words.some((word) => word === word.toUpperCase());
  return {
    text: words.join(", "),
    side: "provider",
    note: `${words.length} → ${new Set(Object.values(report.statuses)).size}`,
    odd: capsed
  };
};

const callbackCell = (report: Report): Cell => {
  if (!report.callback.supported) return { text: "не описан", note: "статус опросом", odd: true };
  return {
    text: report.callback.signature_header ?? "без подписи",
    side: "provider",
    note: report.callback.algorithm ?? undefined
  };
};

const warningWord = (count: number) => {
  const tail = count % 100;
  if (tail >= 11 && tail <= 14) return "предупреждений";
  const last = count % 10;
  if (last === 1) return "предупреждение";
  if (last >= 2 && last <= 4) return "предупреждения";
  return "предупреждений";
};

const missedCell = (report: Report): Cell => {
  const stubs = Object.entries(report.roles)
    .filter(([, role]) => !isBound(role))
    .map(([name]) => name);
  if (stubs.length === 0) return { text: "всё распознано", side: "contract" };
  const count = report.warnings.length;
  return { text: stubs.join(", "), note: `${count} ${warningWord(count)}`, odd: true };
};

const ROWS: { key: string; title: string; hint: string; of: (report: Report) => Cell }[] = [
  { key: "create", title: "Операция создания", hint: "operationId и endpoint", of: createCell },
  { key: "amount", title: "Единицы суммы", hint: "тип поля и множитель", of: amountCell },
  { key: "auth", title: "Авторизация", hint: "securitySchemes", of: authCell },
  { key: "statuses", title: "Статусы", hint: "слова провайдера → статусы контракта", of: statusCell },
  { key: "callback", title: "Уведомления", hint: "webhook и подпись", of: callbackCell },
  { key: "missed", title: "Что не распознано", hint: "роли-заглушки", of: missedCell }
];

export const compareRows = (runs: Record<string, BuildOutcome | undefined>): CompareRow[] =>
  ROWS.map((row) => ({
    key: row.key,
    title: row.title,
    hint: row.hint,
    cells: Object.fromEntries(
      Object.entries(runs).map(([provider, run]) => [
        provider,
        run ? row.of(run.report) : { text: "…" }
      ])
    )
  }));

const NARRATIVE = ["novapay", "swiftpay", "kassabox", "nordbank"];

export const orderProviders = (names: string[]): string[] =>
  [...names].sort((a, b) => {
    const left = NARRATIVE.indexOf(a);
    const right = NARRATIVE.indexOf(b);
    return (left < 0 ? NARRATIVE.length : left) - (right < 0 ? NARRATIVE.length : right);
  });
