import { baseRulesData } from "virtual:base-rules";

export interface Rule {
  field: string;
  pattern: string;
  weight: number;
}

export interface VetoRule {
  field: string;
  pattern: string;
}

export interface Archetype {
  name: string;
  rules: Rule[];
  veto: VetoRule[];
}

export interface FieldGroup {
  field: string;
  patterns: string[];
}

export interface BaseRules {
  archetypes: Archetype[];
  statusPatterns: { group: string; patterns: string[] }[];
  errorSemantics: { code: string; meaning: string }[];
  payloadPatterns: FieldGroup[];
  requisitePatterns: FieldGroup[];
  pathPatterns: FieldGroup[];
  callbackFields: FieldGroup[];
  headers: FieldGroup[];
  amountUnits: { minorPatterns: string[]; multiplier: number; minorRequiresInteger: boolean };
  amountTextRules: { kind: string; comparison: string; pattern: string }[];
}

export const baseRules = (): BaseRules => baseRulesData;

export const archetypeTitles: Record<string, string> = {
  creation: "создание операции",
  status_lookup: "запрос статуса",
  callback: "приём уведомления",
  cancellation: "отмена операции"
};

export const fieldTitles: Record<string, string> = {
  operation_id: "operationId",
  http_method: "метод",
  path: "путь",
  summary: "описание",
  tags: "теги"
};
