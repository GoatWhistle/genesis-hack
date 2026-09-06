import { useEffect, useSyncExternalStore } from "react";
import { humanAge, rememberVisit, readHistory, type RunVisit } from "~/shared/lib/history";

const listeners = new Set<() => void>();
let snapshot: RunVisit[] = readHistory();

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

const remember = (provider: string, contract: string) => {
  const latest = rememberVisit(provider, contract);
  const same =
    latest.length === snapshot.length &&
    latest.every((visit, index) => {
      const old = snapshot[index];
      return old !== undefined && old.provider === visit.provider && old.contract === visit.contract;
    });
  if (same) return;
  snapshot = latest;
  for (const listener of listeners) listener();
};

const SHOWN = 3;

interface LabHistoryProps {
  provider: string;
  contract: string;
  onPick: (provider: string, contract: string) => void;
}

export const LabHistory = ({ provider, contract, onPick }: LabHistoryProps) => {
  const visits = useSyncExternalStore(subscribe, () => snapshot);

  useEffect(() => {
    remember(provider, contract);
  }, [provider, contract]);

  const earlier = visits
    .filter((visit) => visit.provider !== provider || visit.contract !== contract)
    .slice(0, SHOWN);

  if (earlier.length === 0) return null;

  return (
    <nav className="lab-history" aria-label="Недавние разборы">
      <span className="label lab-history-label">Недавно смотрели</span>
      <ul className="lab-history-list">
        {earlier.map((visit) => (
          <li key={`${visit.provider}:${visit.contract}`}>
            <button
              type="button"
              className="lab-history-item"
              onClick={() => onPick(visit.provider, visit.contract)}
            >
              <span className="mono side-provider">{visit.provider}</span>
              <span className="lab-history-sep" aria-hidden="true">
                ×
              </span>
              <span className="mono side-contract">{visit.contract}</span>
              <span className="lab-history-age">{humanAge(visit.seen)}</span>
            </button>
          </li>
        ))}
      </ul>
    </nav>
  );
};
