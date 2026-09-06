import { parse } from "yaml";
import { ruleFile } from "~/shared/api/rules";

export interface ContractRoleView {
  name: string;
  title: string;
  archetype: string;
  traits: string[];
  threshold: number;
  required: boolean;
}

export interface ContractView {
  name: string;
  title: string;
  roles: ContractRoleView[];
  statuses: { own: string; group: string }[];
  errors: { semantic: string; code: string }[];
}

interface RawContract {
  contract?: { title?: string };
  classification?: {
    order?: string[];
    required?: string[];
    thresholds?: Record<string, number>;
    roles?: Record<string, { title?: string; archetype?: string; traits?: string[] }>;
  };
  statuses?: Record<string, string>;
  errors?: { semantics?: Record<string, { code?: string }> };
}

export const contractNamesInRules = ["space_payments", "plain_client"];

const readContract = (name: string): ContractView | undefined => {
  const source = ruleFile(`contracts/${name}/contract.yml`)?.content;
  if (!source) return undefined;

  const raw = (parse(source) ?? {}) as RawContract;
  const classification = raw.classification ?? {};
  const order = classification.order ?? [];
  const required = new Set(classification.required ?? []);
  const thresholds = classification.thresholds ?? {};
  const fallback = thresholds.default ?? 8;

  return {
    name,
    title: raw.contract?.title ?? name,
    roles: order.map((role) => {
      const body = classification.roles?.[role] ?? {};
      return {
        name: role,
        title: body.title ?? role,
        archetype: body.archetype ?? "",
        traits: body.traits ?? [],
        threshold: thresholds[role] ?? fallback,
        required: required.has(role)
      };
    }),
    statuses: Object.entries(raw.statuses ?? {}).map(([own, group]) => ({ own, group })),
    errors: Object.entries(raw.errors?.semantics ?? {}).map(([semantic, body]) => ({
      semantic,
      code: body?.code ?? ""
    }))
  };
};

let cached: ContractView[] | undefined;

export const contractViews = (): ContractView[] => {
  cached ??= contractNamesInRules
    .map(readContract)
    .filter((view): view is ContractView => Boolean(view));
  return cached;
};

export const archetypeRoleMap = (): { archetype: string; byContract: Record<string, ContractRoleView> }[] => {
  const views = contractViews();
  const order: string[] = [];

  for (const view of views) {
    for (const role of view.roles) {
      if (role.archetype && !order.includes(role.archetype)) order.push(role.archetype);
    }
  }

  return order.map((archetype) => {
    const byContract: Record<string, ContractRoleView> = {};
    for (const view of views) {
      const role = view.roles.find((item) => item.archetype === archetype);
      if (role) byContract[view.name] = role;
    }
    return { archetype, byContract };
  });
};
