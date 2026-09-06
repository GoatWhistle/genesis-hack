import type { Archetype, Rule } from "~/shared/model/base";
import { baseRules } from "~/shared/model/base";
import type { Candidate } from "~/shared/model/match";
import { scoreArchetype } from "~/shared/model/match";

export interface Operation {
  provider: string;
  candidate: Candidate;
}

interface SandboxOperation {
  provider: string;
  operationId: string;
  method: string;
  path: string;
  summary: string;
}

const OPERATIONS: SandboxOperation[] = [
  {
    provider: "novapay",
    operationId: "create_payout",
    method: "post",
    path: "/payouts",
    summary: "Создать выплату"
  },
  {
    provider: "novapay",
    operationId: "get_payout_status",
    method: "get",
    path: "/payouts/{payout_id}",
    summary: "Получить статус выплаты"
  },
  {
    provider: "novapay",
    operationId: "payout_webhook",
    method: "post",
    path: "/webhooks/payout",
    summary: "Webhook уведомление о смене статуса"
  },
  {
    provider: "novapay",
    operationId: "cancel_payout",
    method: "post",
    path: "/payouts/{payout_id}/cancel",
    summary: "Отменить выплату"
  },
  {
    provider: "swiftpay",
    operationId: "submit_transfer",
    method: "post",
    path: "/transfers",
    summary: "Отправить перевод"
  },
  {
    provider: "swiftpay",
    operationId: "fetch_transfer",
    method: "get",
    path: "/transfers/{transfer_id}",
    summary: "Узнать состояние перевода"
  },
  {
    provider: "swiftpay",
    operationId: "revoke_transfer",
    method: "post",
    path: "/transfers/{transfer_id}/cancel",
    summary: "Отозвать новый перевод"
  },
  {
    provider: "nordbank",
    operationId: "create_payment_order",
    method: "post",
    path: "/payment-orders",
    summary: "Создать платёжное поручение"
  },
  {
    provider: "nordbank",
    operationId: "get_payment_order",
    method: "get",
    path: "/payment-orders/{paymentId}",
    summary: "Состояние платёжного поручения"
  },
  {
    provider: "nordbank",
    operationId: "revoke_payment_order",
    method: "post",
    path: "/payment-orders/{paymentId}/revocation",
    summary: "Отозвать платёжное поручение"
  },
  {
    provider: "kassabox",
    operationId: "make_transfer",
    method: "post",
    path: "/v1/transfers",
    summary: "Создать перевод"
  },
  {
    provider: "kassabox",
    operationId: "transfer_info",
    method: "get",
    path: "/v1/transfers/{transferNo}",
    summary: "Получить сведения о переводе"
  },
  {
    provider: "kassabox",
    operationId: "abort_transfer",
    method: "post",
    path: "/v1/transfers/{transferNo}/abort",
    summary: "Остановить перевод до передачи в банк"
  }
];

export const sandboxProviders = ["novapay", "swiftpay", "nordbank", "kassabox"];

export const operations: Operation[] = OPERATIONS.map((item) => ({
  provider: item.provider,
  candidate: {
    operationId: item.operationId,
    method: item.method,
    path: item.path,
    summary: item.summary,
    tags: item.operationId.includes("webhook") ? "webhook" : ""
  }
}));

export interface Assignment {
  provider: string;
  byArchetype: Record<string, { operationId: string; score: number } | undefined>;
}

export const thresholds: Record<string, number> = {
  creation: 10,
  status_lookup: 8,
  callback: 8,
  cancellation: 8
};

export const assign = (archetypes: Archetype[]): Assignment[] =>
  sandboxProviders.map((provider) => {
    const mine = operations.filter((item) => item.provider === provider);
    const taken = new Set<string>();
    const byArchetype: Assignment["byArchetype"] = {};

    for (const archetype of archetypes) {
      const threshold = thresholds[archetype.name] ?? 8;
      let best: { operationId: string; score: number } | undefined;

      for (const operation of mine) {
        if (taken.has(operation.candidate.operationId)) continue;
        const scored = scoreArchetype(archetype, operation.candidate);
        if (scored.vetoed || scored.score < threshold) continue;
        if (!best || scored.score > best.score) {
          best = { operationId: operation.candidate.operationId, score: scored.score };
        }
      }

      if (best) taken.add(best.operationId);
      byArchetype[archetype.name] = best;
    }

    return { provider, byArchetype };
  });

export const withPatchedRule = (
  archetypes: Archetype[],
  archetypeName: string,
  ruleIndex: number,
  patch: Partial<Rule>
): Archetype[] =>
  archetypes.map((archetype) =>
    archetype.name === archetypeName
      ? {
          ...archetype,
          rules: archetype.rules.map((rule, index) =>
            index === ruleIndex ? { ...rule, ...patch } : rule
          )
        }
      : archetype
  );

export const cloneArchetypes = (): Archetype[] =>
  baseRules().archetypes.map((archetype) => ({
    ...archetype,
    rules: archetype.rules.map((rule) => ({ ...rule })),
    veto: archetype.veto.map((rule) => ({ ...rule }))
  }));
