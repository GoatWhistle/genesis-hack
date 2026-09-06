import { useCallback, useEffect, useRef, useState } from "react";
import { Mark } from "~/shared/design/Mark";
import { ROUTES, type RoutePath } from "./routes";

interface Props {
  path: RoutePath;
  go: (path: RoutePath) => void;
}

interface RailState {
  overflow: boolean;
  atStart: boolean;
  atEnd: boolean;
}

const IDLE: RailState = { overflow: false, atStart: true, atEnd: true };

export const SiteHeader = ({ path, go }: Props) => {
  const railRef = useRef<HTMLDivElement>(null);
  const [rail, setRail] = useState<RailState>(IDLE);

  const measure = useCallback(() => {
    const node = railRef.current;
    if (!node) return;
    const slack = node.scrollWidth - node.clientWidth;
    setRail({
      overflow: slack > 1,
      atStart: node.scrollLeft <= 1,
      atEnd: node.scrollLeft >= slack - 1
    });
  }, []);

  useEffect(() => {
    measure();
    const node = railRef.current;
    if (!node) return;
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, [measure]);

  useEffect(() => {
    const node = railRef.current;
    const active = node?.querySelector<HTMLElement>('[data-active="true"]');
    active?.scrollIntoView({ block: "nearest", inline: "nearest" });
  }, [path]);

  return (
    <header className="site-header">
      <div className="shell-wide site-header-inner">
        <button className="site-mark" onClick={() => go("/")} aria-label="RSOCKET, на начало">
          <Mark />
          <span className="site-wordmark" aria-hidden="true">
            <b>R</b>SOCKET
          </span>
        </button>
        <nav aria-label="Разделы сайта" className="site-nav-rail-wrap">
          <div
            className="site-nav-rail scroll-x"
            ref={railRef}
            onScroll={measure}
            data-overflow={rail.overflow}
            data-at-start={rail.atStart}
            data-at-end={rail.atEnd}
          >
            <ul className="site-nav">
              {ROUTES.filter((route) => route.path !== "/").map((route) => (
                <li key={route.path}>
                  <button
                    className="site-nav-item"
                    data-active={path === route.path}
                    aria-current={path === route.path ? "page" : undefined}
                    onClick={() => go(route.path)}
                  >
                    {route.nav}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </nav>
      </div>
    </header>
  );
};
