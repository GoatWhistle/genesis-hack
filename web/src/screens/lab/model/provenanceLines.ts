import type { Condition, Role } from "~/shared/api/types";
import { isBound } from "~/shared/api/types";

export type SourceKind =
  | "role"
  | "condition"
  | "status"
  | "event"
  | "amount"
  | "callback"
  | "auth"
  | "base_url";

export interface ProvenanceSource {
  id: string;
  kind: SourceKind;
  title: string;
  summary: string;
  details: string[];
  side: "provider" | "contract" | "ink";
}

export interface ProvenanceMap {
  sources: Map<string, ProvenanceSource>;
  linesBySource: Map<string, number[]>;
  sourceByLine: Map<number, string>;
  explained: number;
  total: number;
}

export const isRubyLine = (line: string) => line.trim().length > 0;

export const roleSummary = (role: Role) =>
  isBound(role)
    ? `Операция ${role.operation} назначена на роль по правилам: счёт ${role.score} при пороге ${role.threshold}.`
    : `Роль осталась заглушкой. ${role.why}.`;

export const roleDetails = (role: Role): string[] =>
  isBound(role)
    ? [`${role.endpoint} — ${role.operation}`, ...role.matched_rules]
    : ["метод остался в файле, но сразу возвращает отказ: догадка выглядела бы как рабочий код"];

export const conditionSummary = (condition: Condition) => {
  const value = Array.isArray(condition.value) ? condition.value.join(", ") : String(condition.value);
  return `Ограничение ${condition.code}: проверка ${condition.checks}, значение ${value}.`;
};

export const methodPattern = (name: string) => new RegExp(`^\\s*def\\s+${name}\\b`);

export const at = (lines: string[], index: number) => lines[index] ?? "";

export const bodyEnd = (lines: string[], from: number) => {
  const indent = at(lines, from).search(/\S/);
  for (let i = from + 1; i < lines.length; i += 1) {
    const line = at(lines, i);
    if (!isRubyLine(line)) continue;
    if (line.search(/\S/) === indent && /^\s*end\b/.test(line)) return i;
    if (line.search(/\S/) < indent) return i - 1;
  }
  return lines.length - 1;
};

export const leadingComment = (lines: string[], from: number) => {
  let start = from;
  while (start > 0 && /^\s*#/.test(at(lines, start - 1))) start -= 1;
  return start;
};

export const constantBlock = (lines: string[], name: string): number[] => {
  const open = lines.findIndex((line) => new RegExp(`^\\s*${name}\\s*=`).test(line));
  if (open === -1) return [];
  const found = [open];
  if (/[{[]\s*$/.test(at(lines, open))) {
    for (let i = open + 1; i < lines.length; i += 1) {
      found.push(i);
      if (/^\s*[}\]]/.test(at(lines, i))) break;
    }
  }
  return found;
};

export interface Claim {
  source: ProvenanceSource;
  lines: number[];
}

export const methodSpan = (lines: string[], method: string): number[] => {
  const head = lines.findIndex((line) => methodPattern(method).test(line));
  if (head === -1) return [];
  const from = leadingComment(lines, head);
  const to = bodyEnd(lines, head);
  const span: number[] = [];
  for (let i = from; i <= to; i += 1) if (isRubyLine(at(lines, i))) span.push(i);
  return span;
};
