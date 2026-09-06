import { useEffect, useState } from "react";
import "./slidingplate.css";

interface Box {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface Props {
  host: HTMLElement | null;
  activeKey: string | undefined;
  className?: string;
}

const lastBox = new WeakMap<HTMLElement, Box>();

const boxOf = (host: HTMLElement, active: HTMLElement): Box => {
  const hostBox = host.getBoundingClientRect();
  const box = active.getBoundingClientRect();
  return {
    left: box.left - hostBox.left,
    top: box.top - hostBox.top,
    width: box.width,
    height: box.height
  };
};

const paint = (node: HTMLElement, box: Box) => {
  node.style.transform = `translate(${box.left}px, ${box.top}px)`;
  node.style.width = `${box.width}px`;
  node.style.height = `${box.height}px`;
};

const settle = (node: HTMLElement, box: Box) => {
  node.style.transition = "none";
  paint(node, box);
  void node.offsetWidth;
  node.style.transition = "";
};

const show = (node: HTMLElement, visible: boolean) => {
  node.hidden = !visible;
};

const prime = (node: HTMLElement, box: Box) => {
  if (node.dataset.primed === "true") return;
  node.dataset.primed = "true";
  settle(node, box);
};

export const SlidingPlate = ({ host, activeKey, className }: Props) => {
  const [node, setNode] = useState<HTMLSpanElement | null>(null);

  useEffect(() => {
    if (!host || !node) return;

    const measure = () => {
      const active = host.querySelector<HTMLElement>('[data-plate="true"]');

      if (!active) {
        show(node, false);
        return;
      }

      const box = boxOf(host, active);
      const known = lastBox.get(host);
      lastBox.set(host, box);

      prime(node, known ?? box);
      paint(node, box);
      show(node, true);
    };

    measure();
    const frame = requestAnimationFrame(measure);
    const observer = new ResizeObserver(measure);
    observer.observe(host);
    for (const child of host.children) {
      if (child !== node) observer.observe(child);
    }
    window.addEventListener("resize", measure);

    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener("resize", measure);
    };
  }, [host, node, activeKey]);

  return (
    <span
      ref={setNode}
      className={className ? `sliding-plate ${className}` : "sliding-plate"}
      aria-hidden="true"
    />
  );
};
