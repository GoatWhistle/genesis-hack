import type { BuildOutcome, ContractProfile } from "./types";
import index from "~/data/runs/index.json";
import contracts from "~/data/runs/contracts.json";

const lazyRunLoaders = import.meta.glob<{ default: BuildOutcome }>("../../data/runs/*.*.json");

const runName = (provider: string, contract: string) => `${provider}.${contract}`;
const runModulePath = (name: string) => `../../data/runs/${name}.json`;

const openedRuns = new Map<string, BuildOutcome>();

export const providers: string[] = index.providers;
export const contractNames: string[] = index.contracts;
export const bakedAt: string = index.baked;
export const profiles = contracts as ContractProfile[];

export const defaultProvider = providers[0] ?? "novapay";
export const defaultContract =
  profiles.find((profile) => profile.default)?.name ?? contractNames[0] ?? "space_payments";

export const hasRun = (provider: string, contract: string) =>
  runModulePath(runName(provider, contract)) in lazyRunLoaders;

export const loadRun = async (provider: string, contract: string): Promise<BuildOutcome> => {
  const name = runName(provider, contract);
  const opened = openedRuns.get(name);
  if (opened) return opened;

  const load = lazyRunLoaders[runModulePath(name)];
  if (!load) throw new Error(`нет запечённого прогона: ${name}`);

  const outcome = (await load()).default;
  openedRuns.set(name, outcome);
  return outcome;
};

export const cachedRun = (provider: string, contract: string) =>
  openedRuns.get(runName(provider, contract));

export const profileOf = (contract: string): ContractProfile | undefined =>
  profiles.find((profile) => profile.name === contract);

export const roleOrder = (contract: string): string[] =>
  profileOf(contract)?.roles.map((role) => role.name) ?? [];

export const roleTitle = (contract: string, role: string): string =>
  profileOf(contract)?.roles.find((item) => item.name === role)?.title ?? role;

export const roleMeta = (contract: string, role: string) =>
  profileOf(contract)?.roles.find((item) => item.name === role);
