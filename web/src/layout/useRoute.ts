import { useCallback, useEffect, useState } from "react";
import { ROUTES, isRoute, type RoutePath } from "./routes";

const SITE_NAME = "RSOCKET";
const SITE_ABOUT = "интеграция по описанию API";

const readPathFromLocation = (): RoutePath => {
  const path = window.location.pathname.replace(/\/+$/, "") || "/";
  return isRoute(path) ? path : "/";
};

const straightenUnknownAddress = () => {
  const typed = window.location.pathname.replace(/\/+$/, "") || "/";
  if (isRoute(typed)) return;
  window.history.replaceState({}, "", `/${window.location.search}`);
};

const documentTitleFor = (path: RoutePath): string => {
  if (path === "/") return `${SITE_NAME} — ${SITE_ABOUT}`;
  const section = ROUTES.find((route) => route.path === path)?.title ?? SITE_NAME;
  return `${section} — ${SITE_NAME}`;
};

export const useRoute = () => {
  const [path, setPath] = useState<RoutePath>(readPathFromLocation);

  useEffect(() => {
    document.title = documentTitleFor(path);
  }, [path]);

  useEffect(() => {
    straightenUnknownAddress();
    const onPop = () => {
      straightenUnknownAddress();
      setPath(readPathFromLocation());
    };
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  const go = useCallback((next: RoutePath, search = "") => {
    const address = `${next}${search}`;
    if (address === `${window.location.pathname}${window.location.search}`) return;
    window.history.pushState({}, "", address);
    setPath(next);
  }, []);

  return { path, go };
};

const writeParam = (name: string, value: string, fallback: string, replace: boolean) => {
  const params = new URLSearchParams(window.location.search);
  if (value === fallback) params.delete(name);
  else params.set(name, value);
  const query = params.toString();
  const address = `${window.location.pathname}${query ? `?${query}` : ""}`;
  if (replace) window.history.replaceState({}, "", address);
  else window.history.pushState({}, "", address);
};

export const useSearchParam = (
  name: string,
  fallback: string,
  accepts?: (value: string) => boolean
) => {
  const readFromLocation = useCallback(() => {
    const raw = new URLSearchParams(window.location.search).get(name) ?? fallback;
    return accepts && !accepts(raw) ? fallback : raw;
  }, [name, fallback, accepts]);

  const [value, setValue] = useState(readFromLocation);

  const straightenUnknownValue = useCallback(() => {
    const raw = new URLSearchParams(window.location.search).get(name);
    if (raw === null || !accepts || accepts(raw)) return;
    writeParam(name, fallback, fallback, true);
  }, [name, fallback, accepts]);

  useEffect(() => {
    straightenUnknownValue();
    const onPop = () => {
      straightenUnknownValue();
      setValue(readFromLocation());
    };
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, [readFromLocation, straightenUnknownValue]);

  const update = useCallback(
    (next: string) => {
      if (next === readFromLocation()) return;
      setValue(next);
      writeParam(name, next, fallback, false);
    },
    [name, fallback, readFromLocation]
  );

  return [value, update] as const;
};
