import { useState } from "react";
import { SlidingPlate } from "./SlidingPlate";
import "./sidenav.css";

export interface SideNavItem {
  id: string;
  title: string;
}

interface SideNavProps {
  label: string;
  items: readonly SideNavItem[];
  current: string;
  onPick: (id: string) => void;
}

export const SideNav = ({ label, items, current, onPick }: SideNavProps) => {
  const [host, setHost] = useState<HTMLUListElement | null>(null);

  return (
    <nav className="side-nav" aria-label={label}>
      <ul ref={setHost}>
        <SlidingPlate host={host} activeKey={current} className="side-nav-edge" />
        {items.map((item) => {
          const active = item.id === current;

          return (
            <li key={item.id}>
              <button
                type="button"
                className="side-nav-item"
                data-active={active}
                data-plate={active}
                aria-current={active ? "true" : undefined}
                onClick={() => onPick(item.id)}
              >
                <span className="side-nav-text">{item.title}</span>
              </button>
            </li>
          );
        })}
      </ul>
    </nav>
  );
};
