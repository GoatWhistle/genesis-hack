import { LayoutGroup, motion } from "motion/react";
import { useSlideTransition } from "~/shared/lib/motion";
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
  const transition = useSlideTransition();

  return (
    <nav className="side-nav" aria-label={label}>
      <LayoutGroup id={`side-nav-${label}`}>
      <ul>
        {items.map((item) => {
          const active = item.id === current;

          return (
            <li key={item.id}>
              <button
                type="button"
                className="side-nav-item"
                data-active={active}
                aria-current={active ? "true" : undefined}
                onClick={() => onPick(item.id)}
              >
                {active ? (
                  <motion.span
                    layoutId={`side-nav-${label}`}
                    className="side-nav-edge"
                    transition={transition}
                    aria-hidden="true"
                  />
                ) : null}
                <span className="side-nav-text">{item.title}</span>
              </button>
            </li>
          );
        })}
      </ul>
      </LayoutGroup>
    </nav>
  );
};
