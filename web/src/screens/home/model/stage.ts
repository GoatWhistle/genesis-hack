import type { BuildOutcome } from "~/shared/api/types";
import { isBound } from "~/shared/api/types";
import { roleOrder, roleTitle } from "~/shared/api/runs";
import { matchCandidate, snakeCase } from "~/shared/model/match";

export interface StageRule {
  field: string;
  pattern: string;
}

export interface StageCandidate {
  operation: string;
  score: number;
  possible: number;
  vetoed: boolean;
  reason: string;
}

export interface StageBeat {
  role: string;
  title: string;
  threshold: number;
  operation: string;
  endpoint: string;
  verb: string;
  path: string;
  score: number;
  archetype: string;
  rules: StageRule[];
  rivals: StageCandidate[];
  code: string[];
}

const ARCHETYPE_OF_ROLE: Record<string, string> = {
  create_request: "creation",
  fetch_status: "status_lookup",
  process_callback: "callback",
  cancel_request: "cancellation",
  send_payout: "creation",
  payout_state: "status_lookup",
  read_callback: "callback",
  cancel_payout: "cancellation"
};

const parseRule = (raw: string): StageRule => {
  const [field, rest] = raw.split(" =~ ");
  return { field: field ?? raw, pattern: rest ?? "" };
};

const methodSource = (file: string, name: string): string[] => {
  const lines = file.split("\n");
  const start = lines.findIndex((line) => new RegExp(`^\\s*def ${name}\\b`).test(line));
  if (start < 0) return [`def ${name}`, "end"];

  const indent = lines[start]?.match(/^\s*/)?.[0].length ?? 0;
  let stop = start + 1;
  while (stop < lines.length) {
    const line = lines[stop] ?? "";
    if (line.trim() === "end" && (line.match(/^\s*/)?.[0].length ?? 0) === indent) break;
    stop += 1;
  }

  return lines
    .slice(start, stop + 1)
    .map((line) => line.slice(indent))
    .filter((line) => !line.trim().startsWith("#"));
};

interface PoolItem {
  operation: string;
  endpoint: string;
}

const rivalsFor = (role: string, winner: string, pool: PoolItem[]): StageCandidate[] => {
  const wanted = ARCHETYPE_OF_ROLE[role];

  return pool
    .filter((item) => item.operation !== winner)
    .map((item) => {
      const [verb, path] = item.endpoint.split(" ");
      const { scores } = matchCandidate({
        operationId: snakeCase(item.operation),
        method: (verb ?? "post").toLowerCase(),
        path: path ?? "",
        summary: "",
        tags: ""
      });

      const here = scores.find((entry) => entry.name === wanted);
      const vetoHit = here?.veto.find((entry) => entry.hit);

      return {
        operation: item.operation,
        score: here?.score ?? 0,
        possible: here?.possible ?? 0,
        vetoed: here?.vetoed ?? false,
        reason: vetoHit?.rule.pattern ?? `${here?.score ?? 0} очков`
      };
    })
    .slice(0, 3);
};

export const stageBeats = (run: BuildOutcome, contract: string): StageBeat[] => {
  const file = run.files[`${run.provider}_service.rb`] ?? "";

  const pool: PoolItem[] = roleOrder(contract).flatMap((name) => {
    const role = run.report.roles[name];
    return role && isBound(role) ? [{ operation: role.operation, endpoint: role.endpoint }] : [];
  });

  return roleOrder(contract).flatMap((name) => {
    const role = run.report.roles[name];
    if (!role || !isBound(role)) return [];
    const [verb, path] = role.endpoint.split(" ");

    return [
      {
        role: name,
        title: roleTitle(contract, name),
        threshold: role.threshold,
        operation: role.operation,
        endpoint: role.endpoint,
        verb: verb ?? "POST",
        path: path ?? role.endpoint,
        score: role.score,
        archetype: ARCHETYPE_OF_ROLE[name] ?? name,
        rules: role.matched_rules.map(parseRule),
        rivals: rivalsFor(name, role.operation, pool),
        code: methodSource(file, name)
      }
    ];
  });
};

export const beatWindow = (index: number, count: number) => {
  const span = 1 / Math.max(count, 1);
  return { from: index * span, to: (index + 1) * span };
};
