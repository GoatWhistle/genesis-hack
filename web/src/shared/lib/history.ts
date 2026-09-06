export interface RunVisit {
  provider: string;
  contract: string;
  seen: number;
}

export const HISTORY_LIMIT = 8;

const STORAGE_KEY = "rsocket.history";

const isVisit = (value: unknown): value is RunVisit => {
  if (typeof value !== "object" || value === null) return false;
  const item = value as Record<string, unknown>;
  return (
    typeof item.provider === "string" &&
    typeof item.contract === "string" &&
    typeof item.seen === "number" &&
    Number.isFinite(item.seen)
  );
};

export const parseVisits = (raw: string | null): RunVisit[] => {
  if (!raw) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(isVisit).slice(0, HISTORY_LIMIT);
  } catch {
    return [];
  }
};

export const withVisit = (visits: RunVisit[], visit: RunVisit): RunVisit[] => {
  const rest = visits.filter(
    (item) => item.provider !== visit.provider || item.contract !== visit.contract
  );
  return [visit, ...rest].slice(0, HISTORY_LIMIT);
};

export const readHistory = (): RunVisit[] => {
  try {
    return parseVisits(window.localStorage.getItem(STORAGE_KEY));
  } catch {
    return [];
  }
};

export const writeHistory = (visits: RunVisit[]): boolean => {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(visits));
    return true;
  } catch {
    return false;
  }
};

export const rememberVisit = (provider: string, contract: string, now = Date.now()): RunVisit[] => {
  const next = withVisit(readHistory(), { provider, contract, seen: now });
  writeHistory(next);
  return next;
};

export const forgetHistory = (): boolean => {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
    return true;
  } catch {
    return false;
  }
};

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const minuteWord = (count: number) => {
  const tail = count % 100;
  if (tail >= 11 && tail <= 14) return "минут";
  const last = count % 10;
  if (last === 1) return "минуту";
  if (last >= 2 && last <= 4) return "минуты";
  return "минут";
};

const hourWord = (count: number) => {
  const tail = count % 100;
  if (tail >= 11 && tail <= 14) return "часов";
  const last = count % 10;
  if (last === 1) return "час";
  if (last >= 2 && last <= 4) return "часа";
  return "часов";
};

const dayWord = (count: number) => {
  const tail = count % 100;
  if (tail >= 11 && tail <= 14) return "дней";
  const last = count % 10;
  if (last === 1) return "день";
  if (last >= 2 && last <= 4) return "дня";
  return "дней";
};

export const humanAge = (seen: number, now = Date.now()): string => {
  const gap = now - seen;
  if (gap < 0) return "только что";
  if (gap < MINUTE) return "только что";

  if (gap < HOUR) {
    const minutes = Math.floor(gap / MINUTE);
    return `${minutes} ${minuteWord(minutes)} назад`;
  }

  if (gap < DAY) {
    const hours = Math.floor(gap / HOUR);
    return `${hours} ${hourWord(hours)} назад`;
  }

  const days = Math.floor(gap / DAY);
  if (days === 1) return "вчера";
  if (days < 7) return `${days} ${dayWord(days)} назад`;
  if (days < 31) {
    const weeks = Math.floor(days / 7);
    return weeks === 1 ? "неделю назад" : `${weeks} недели назад`;
  }
  return "давно";
};
