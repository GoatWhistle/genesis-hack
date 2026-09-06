import type { Report } from "~/shared/api/types";
import { isBound } from "~/shared/api/types";
import type { Claim, ProvenanceMap } from "./provenanceLines";
import {
  at,
  bodyEnd,
  conditionSummary,
  constantBlock,
  isRubyLine,
  leadingComment,
  methodPattern,
  roleDetails,
  roleSummary
} from "./provenanceLines";
import { flatClaims } from "./provenanceFlat";

export type { ProvenanceMap, ProvenanceSource, SourceKind } from "./provenanceLines";

const emptyMap = (): ProvenanceMap => ({
  sources: new Map(),
  linesBySource: new Map(),
  sourceByLine: new Map(),
  explained: 0,
  total: 0
});

const roleClaims = (report: Report, lines: string[], methodOf: Map<string, string>): Claim[] => {
  const claims: Claim[] = [];

  for (const [name, role] of Object.entries(report.roles)) {
    const method = methodOf.get(name) ?? name;
    const head = lines.findIndex((line) => methodPattern(method).test(line));
    if (head === -1) continue;

    const from = leadingComment(lines, head);
    const to = bodyEnd(lines, head);
    const span: number[] = [];
    for (let i = from; i <= to; i += 1) if (isRubyLine(at(lines, i))) span.push(i);

    claims.push({
      source: {
        id: `role:${name}`,
        kind: "role",
        title: name,
        summary: roleSummary(role),
        details: roleDetails(role),
        side: isBound(role) ? "contract" : "ink"
      },
      lines: span
    });
  }

  return claims;
};

const pairClaims = (
  lines: string[],
  block: number[],
  pairs: [string, string][],
  kind: "status" | "event",
  label: string
): Claim[] =>
  pairs.flatMap(([from, to]) => {
    const key = from.toLowerCase();
    const hit = block.find((index) => {
      const [left = "", right = ""] = at(lines, index).split("=>");
      return left.includes(`"${key}"`) && (right.includes(`"${to}"`) || right.includes(`:${to}`));
    });
    if (hit === undefined) return [];
    return [
      {
        source: {
          id: `${kind}:${from}`,
          kind,
          title: from,
          summary: `Слово провайдера «${from}» переведено в состояние контракта «${to}».`,
          details: [`словарь собран по перечислению в описании ${label.toLowerCase()}`],
          side: "provider" as const
        },
        lines: [hit]
      }
    ];
  });

const conditionClaims = (report: Report, lines: string[]): Claim[] =>
  report.conditions.flatMap((condition) => {
    const constant =
      condition.kind === "min_amount"
        ? "MIN_AMOUNT"
        : condition.kind === "max_amount"
          ? "MAX_AMOUNT"
          : condition.kind === "currency"
            ? "ALLOWED_CURRENCIES"
            : undefined;

    const span = new Set<number>();
    if (constant) {
      for (const index of constantBlock(lines, constant)) span.add(index);
      const before = [...span][0];
      if (before !== undefined && /^\s*#/.test(at(lines, before - 1))) span.add(before - 1);
    }
    lines.forEach((line, index) => {
      if (line.includes(`"${condition.code}"`)) span.add(index);
    });

    if (span.size === 0) return [];
    return [
      {
        source: {
          id: `condition:${condition.code}`,
          kind: "condition",
          title: condition.code,
          summary: conditionSummary(condition),
          details: [`взято из описания: ${condition.source}`],
          side: "provider" as const
        },
        lines: [...span].sort((a, b) => a - b)
      }
    ];
  });

export const buildProvenance = (
  report: Report,
  code: string,
  methodOf: Map<string, string>
): ProvenanceMap => {
  if (!code) return emptyMap();

  const lines = code.split("\n");
  const claims = [
    ...roleClaims(report, lines, methodOf),
    ...conditionClaims(report, lines),
    ...pairClaims(
      lines,
      constantBlock(lines, "STATUS_MAP").concat(constantBlock(lines, "STATE_MAP")),
      Object.entries(report.statuses),
      "status",
      "Состояние"
    ),
    ...pairClaims(lines, constantBlock(lines, "EVENT_MAP"), Object.entries(report.events), "event", "Событие"),
    ...flatClaims(report, lines)
  ];

  const map = emptyMap();
  map.total = lines.filter(isRubyLine).length;

  for (const claim of claims) {
    if (claim.lines.length === 0) continue;
    map.sources.set(claim.source.id, claim.source);
    map.linesBySource.set(claim.source.id, claim.lines);
    for (const index of claim.lines) {
      if (!map.sourceByLine.has(index)) map.sourceByLine.set(index, claim.source.id);
    }
  }

  map.explained = map.sourceByLine.size;
  return map;
};
