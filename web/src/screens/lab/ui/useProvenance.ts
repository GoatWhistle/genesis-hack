import { createContext, useContext, useMemo, useState } from "react";
import type { ProvenanceMap } from "../model/provenance";

interface ProvenanceLink {
  map: ProvenanceMap;
  active?: string;
  setActive: (id?: string) => void;
}

const fallback: ProvenanceLink = {
  map: {
    sources: new Map(),
    linesBySource: new Map(),
    sourceByLine: new Map(),
    explained: 0,
    total: 0
  },
  setActive: () => undefined
};

export const ProvenanceContext = createContext<ProvenanceLink>(fallback);

export const useProvenanceLink = () => useContext(ProvenanceContext);

export const useProvenanceState = (map: ProvenanceMap): ProvenanceLink => {
  const [active, setActive] = useState<string>();
  return useMemo(() => ({ map, active, setActive }), [map, active]);
};

export const lineWord = (count: number) =>
  count === 1 ? "строка" : count % 10 > 1 && count % 10 < 5 && (count < 12 || count > 14) ? "строки" : "строк";

export const useSourceHandlers = (id: string) => {
  const { map, active, setActive } = useProvenanceLink();
  const known = map.sources.has(id);
  const count = map.linesBySource.get(id)?.length ?? 0;

  return {
    known,
    count,
    label: `${count} ${lineWord(count)} в шаге 5`,
    lit: known && active === id,
    props: known
      ? {
          onMouseEnter: () => setActive(id),
          onMouseLeave: () => setActive(undefined),
          onFocus: () => setActive(id),
          onBlur: () => setActive(undefined),
          tabIndex: 0
        }
      : {}
  };
};
