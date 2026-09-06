export interface BoundRole {
  status: "запрос к провайдеру" | "приём уведомления";
  operation: string;
  endpoint: string;
  score: number;
  threshold: number;
  matched_rules: string[];
}

export interface StubRole {
  status: "заглушка";
  why: string;
}

export type Role = BoundRole | StubRole;

export const isBound = (role: Role): role is BoundRole => role.status !== "заглушка";

export interface Condition {
  code: string;
  kind: string;
  checks: string;
  value: number | string | string[];
  source: string;
}

export interface AmountPlan {
  multiplier: number;
  note: string;
}

export interface CallbackPlan {
  supported: boolean;
  signature_header?: string | null;
  algorithm?: string | null;
  operation_id_field?: string;
}

export interface AuthPlan {
  primary: string | null;
  alternatives: string[];
  notes: string[];
}

export interface Report {
  provider: string;
  contract: string;
  spec: string;
  api: string;
  base_url: string | null;
  roles: Record<string, Role>;
  statuses: Record<string, string>;
  events: Record<string, string>;
  amount: AmountPlan;
  conditions: Condition[];
  callback: CallbackPlan;
  auth: AuthPlan;
  warnings: string[];
}

export interface BuildOutcome {
  provider: string;
  contract: string;
  warnings: string[];
  locations: string[];
  files: Record<string, string>;
  report: Report;
}

export interface ContractRole {
  name: string;
  title: string;
  threshold: number;
  required: boolean;
  traits: string[];
}

export interface ContractProfile {
  name: string;
  title: string;
  default: boolean;
  files: string[];
  outputs: string[];
  roles: ContractRole[];
}
