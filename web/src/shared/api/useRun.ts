import { useEffect, useState } from "react";
import type { BuildOutcome } from "./types";
import { cachedRun, loadRun } from "./runs";
import { build as buildLive } from "./client";

export interface RunState {
  run: BuildOutcome | undefined;
  loading: boolean;
  error: string | undefined;
}

export const useBakedRun = (provider: string, contract: string): RunState => {
  const [loaded, setLoaded] = useState<Record<string, RunState>>({});
  const key = `${provider}.${contract}`;

  useEffect(() => {
    const alreadyAvailableWithoutSetState = cachedRun(provider, contract);
    if (alreadyAvailableWithoutSetState) return;

    let alive = true;
    loadRun(provider, contract)
      .then((run) => {
        if (alive) setLoaded((prev) => ({ ...prev, [key]: { run, loading: false, error: undefined } }));
      })
      .catch((error: Error) => {
        if (alive) {
          setLoaded((prev) => ({
            ...prev,
            [key]: { run: undefined, loading: false, error: error.message }
          }));
        }
      });

    return () => {
      alive = false;
    };
  }, [provider, contract, key]);

  const ready = cachedRun(provider, contract);
  if (ready) return { run: ready, loading: false, error: undefined };
  return loaded[key] ?? { run: undefined, loading: true, error: undefined };
};

export const useLiveBuild = () => {
  const [state, setState] = useState<RunState>({ run: undefined, loading: false, error: undefined });

  const send = async (spec: string, provider: string, contract: string) => {
    setState({ run: undefined, loading: true, error: undefined });
    try {
      const run = await buildLive(spec, provider, contract);
      setState({ run, loading: false, error: undefined });
      return run;
    } catch (error) {
      setState({ run: undefined, loading: false, error: (error as Error).message });
      return undefined;
    }
  };

  const reset = () => setState({ run: undefined, loading: false, error: undefined });

  return { ...state, send, reset };
};
