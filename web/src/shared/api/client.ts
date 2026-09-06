import type { BuildOutcome, ContractProfile } from "./types";

const API = "/api";

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number
  ) {
    super(message);
    this.name = "ApiError";
  }
}

const request = async <T>(path: string, init?: RequestInit): Promise<T> => {
  const response = await fetch(`${API}${path}`, init);
  const text = await response.text();
  if (!response.ok) {
    const reason = (() => {
      try {
        return (JSON.parse(text) as { error?: string }).error ?? text;
      } catch {
        return text;
      }
    })();
    throw new ApiError(reason.slice(0, 400), response.status);
  }
  return JSON.parse(text) as T;
};

export const health = () => request<{ status: string; contracts: string[] }>("/health");

export const fetchContracts = () =>
  request<{ contracts: ContractProfile[] }>("/contracts").then((body) => body.contracts);

export const build = (spec: string, provider: string, contract: string) =>
  request<BuildOutcome>(`/build?${new URLSearchParams({ provider, contract })}`, {
    method: "POST",
    headers: { "Content-Type": "application/yaml" },
    body: spec
  });

export const readRule = (key: string) =>
  request<{ key: string; content: string }>(`/rules/${rulePath(key)}`);

const rulePath = (key: string) => key.split("/").map(encodeURIComponent).join("/");

export const writeRule = (key: string, content: string) =>
  request<{ saved: { key: string; kind: string; bytes: number } }>(`/rules/${rulePath(key)}`, {
    method: "PUT",
    headers: { "Content-Type": "application/yaml" },
    body: content
  });

export const listRules = (prefix = "") =>
  request<{ location: string; files: { key: string; kind: string }[] }>(
    `/rules${prefix ? `?prefix=${encodeURIComponent(prefix)}` : ""}`
  );
