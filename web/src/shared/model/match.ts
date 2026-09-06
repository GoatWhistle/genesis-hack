import type { Archetype, Rule, VetoRule } from "./base";
import { baseRules } from "./base";

export interface Candidate {
  operationId: string;
  method: string;
  path: string;
  summary: string;
  tags: string;
}

export interface RuleHit {
  rule: Rule;
  hit: boolean;
  value: string;
}

export interface VetoHit {
  rule: VetoRule;
  hit: boolean;
  value: string;
}

export interface ArchetypeScore {
  name: string;
  score: number;
  possible: number;
  rules: RuleHit[];
  veto: VetoHit[];
  vetoed: boolean;
}

export interface MatchResult {
  candidate: Candidate;
  scores: ArchetypeScore[];
  winner: ArchetypeScore | undefined;
}

const rubyToJs = (pattern: string) => pattern.replace(/\\A/g, "^").replace(/\\z/g, "$");

export const snakeCase = (name: string) =>
  name
    .replace(/([a-z\d])([A-Z])/g, "$1_$2")
    .replace(/[-\s]+/g, "_")
    .toLowerCase();

export const toRegExp = (pattern: string): RegExp | undefined => {
  try {
    return new RegExp(rubyToJs(pattern), "i");
  } catch {
    return undefined;
  }
};

const valueOf = (candidate: Candidate, field: string): string => {
  if (field === "operation_id") return candidate.operationId;
  if (field === "http_method") return candidate.method;
  if (field === "path") return candidate.path;
  if (field === "summary") return candidate.summary;
  if (field === "tags") return candidate.tags;
  return "";
};

const test = (pattern: string, value: string) => {
  const expression = toRegExp(pattern);
  if (!expression) return false;
  return expression.test(value);
};

export const scoreArchetype = (archetype: Archetype, candidate: Candidate): ArchetypeScore => {
  const rules = archetype.rules.map((rule) => {
    const value = valueOf(candidate, rule.field);
    return { rule, value, hit: test(rule.pattern, value) };
  });

  const veto = archetype.veto.map((rule) => {
    const value = valueOf(candidate, rule.field);
    return { rule, value, hit: test(rule.pattern, value) };
  });

  const vetoed = veto.some((item) => item.hit);
  const score = rules.reduce((sum, item) => sum + (item.hit ? item.rule.weight : 0), 0);
  const possible = archetype.rules.reduce((sum, rule) => sum + rule.weight, 0);

  return { name: archetype.name, score: vetoed ? 0 : score, possible, rules, veto, vetoed };
};

export const matchCandidate = (
  candidate: Candidate,
  archetypes = baseRules().archetypes
): MatchResult => {
  const scores = archetypes.map((archetype) => scoreArchetype(archetype, candidate));
  const alive = scores.filter((item) => !item.vetoed && item.score > 0);
  const winner = alive.reduce<ArchetypeScore | undefined>(
    (best, item) => (!best || item.score > best.score ? item : best),
    undefined
  );

  return { candidate, scores, winner };
};

export const methodFor = (operationId: string): string =>
  /^(get|fetch|show|read|retrieve|list|check|info)/i.test(operationId) ? "get" : "post";

const pathFor = (operationId: string, method: string): string => {
  const name = snakeCase(operationId);
  if (/(webhook|callback|notification|event)/.test(name)) return "/webhooks/payout";
  if (/(cancel|revoke|abort|void)/.test(name)) return "/payouts/{payout_id}/cancel";
  return method === "get" ? "/payouts/{payout_id}" : "/payouts";
};

const KNOWN_SUMMARIES: Record<string, string> = {
  create_payout: "Создать выплату",
  cancel_payout: "Отменить выплату",
  payout_webhook: "Webhook уведомление о смене статуса",
  get_payout_status: "Получить статус выплаты",
  make_transfer: "Создать перевод",
  get_transfer_info: "Получить сведения о переводе",
  revoke_payment_order: "Отозвать платёжное поручение",
  get_payment_status: "Состояние платёжного поручения"
};

export const candidateOf = (operationId: string): Candidate => {
  const method = methodFor(operationId);
  const name = snakeCase(operationId);
  const tags = /(webhook|callback|notification|event)/.test(name) ? "webhook" : "";
  return {
    operationId: name,
    method,
    path: pathFor(operationId, method),
    summary: KNOWN_SUMMARIES[name] ?? "",
    tags
  };
};

export const hasKnownSummary = (operationId: string): boolean =>
  snakeCase(operationId) in KNOWN_SUMMARIES;
