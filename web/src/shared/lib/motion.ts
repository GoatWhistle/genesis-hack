import { useEffect, useState } from "react";
import type { Transition, Variants } from "motion/react";

export const EASE_OUT = [0.25, 1, 0.5, 1] as const;

export const SWAP: Transition = { duration: 0.2, ease: EASE_OUT };
export const SLIDE: Transition = { duration: 0.26, ease: EASE_OUT };
export const QUICK: Transition = { duration: 0.16, ease: EASE_OUT };

export const enterVariants: Variants = {
  hidden: { opacity: 0, y: 6 },
  shown: { opacity: 1, y: 0 },
  gone: { opacity: 0, y: -4 }
};

export const fadeVariants: Variants = {
  hidden: { opacity: 0 },
  shown: { opacity: 1 },
  gone: { opacity: 0 }
};

export const useReducedMotion = () => {
  const [reduced, setReduced] = useState(() => {
    if (typeof window === "undefined" || !window.matchMedia) return false;
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  });

  useEffect(() => {
    if (typeof window === "undefined" || !window.matchMedia) return;
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);

  return reduced;
};

export const useSwapTransition = (): Transition => {
  const reduced = useReducedMotion();
  return reduced ? { duration: 0 } : SWAP;
};

export const useSlideTransition = (): Transition => {
  const reduced = useReducedMotion();
  return reduced ? { duration: 0 } : SLIDE;
};
