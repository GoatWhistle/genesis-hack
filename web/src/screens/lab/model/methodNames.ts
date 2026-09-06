import { roleOrder } from "~/shared/api/runs";

const cache = new Map<string, Map<string, string>>();

export const methodNames = (contract: string): Map<string, string> => {
  const ready = cache.get(contract);
  if (ready) return ready;

  const built = new Map(roleOrder(contract).map((role) => [role, role]));
  cache.set(contract, built);
  return built;
};
