import { useEffect, useState } from "react";
import type { BuildOutcome } from "./types";
import { cachedRun, loadRun, providers } from "./runs";

export type Runs = Record<string, BuildOutcome | undefined>;

const fromCache = (contract: string): Runs =>
  Object.fromEntries(providers.map((provider) => [provider, cachedRun(provider, contract)]));

export const useRunsByProvider = (contract: string) => {
  const [state, setState] = useState<{ contract: string; runs: Runs; error?: string }>({
    contract: "",
    runs: {}
  });

  useEffect(() => {
    let alive = true;

    Promise.all(providers.map((provider) => loadRun(provider, contract)))
      .then((loaded) => {
        if (!alive) return;
        setState({
          contract,
          runs: Object.fromEntries(loaded.map((run, index) => [providers[index] as string, run]))
        });
      })
      .catch((cause: Error) => alive && setState({ contract, runs: {}, error: cause.message }));

    return () => {
      alive = false;
    };
  }, [contract]);

  const fresh = state.contract === contract;
  const runs = fresh && !state.error ? state.runs : fromCache(contract);
  const ready = providers.every((provider) => runs[provider]);
  return { runs, ready, error: fresh ? state.error : undefined };
};

export const useAllRuns = (contract: string): BuildOutcome[] => {
  const [runs, setRuns] = useState<BuildOutcome[]>([]);

  useEffect(() => {
    let alive = true;

    Promise.all(
      providers.map((provider) => loadRun(provider, contract).catch(() => undefined))
    ).then((loaded) => {
      if (!alive) return;
      setRuns(loaded.filter((run): run is BuildOutcome => Boolean(run)));
    });

    return () => {
      alive = false;
    };
  }, [contract]);

  return runs;
};
