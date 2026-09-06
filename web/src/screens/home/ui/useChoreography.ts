import { useCallback, useEffect, useRef, useState } from "react";

const reduced = () =>
  typeof window !== "undefined" &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

export interface Choreography {
  progress: number;
  playing: boolean;
  replay: () => void;
  scrub: (value: number) => void;
  toggle: () => void;
}

export const useChoreography = (duration: number, ready: boolean): Choreography => {
  const [progress, setProgress] = useState(1);
  const [playing, setPlaying] = useState(false);
  const frame = useRef(0);
  const origin = useRef(0);
  const started = useRef(false);

  const stop = useCallback(() => {
    cancelAnimationFrame(frame.current);
    setPlaying(false);
  }, []);

  const run = useCallback(
    (from: number) => {
      cancelAnimationFrame(frame.current);
      if (reduced()) {
        setProgress(1);
        setPlaying(false);
        return;
      }

      origin.current = performance.now() - from * duration;
      setPlaying(true);

      const tick = (now: number) => {
        const value = Math.min(1, (now - origin.current) / duration);
        setProgress(value);
        if (value < 1) frame.current = requestAnimationFrame(tick);
        else setPlaying(false);
      };

      frame.current = requestAnimationFrame(tick);
    },
    [duration]
  );

  useEffect(() => {
    if (!ready || started.current) return;
    started.current = true;
    run(0);
    return () => cancelAnimationFrame(frame.current);
  }, [ready, run]);

  useEffect(() => () => cancelAnimationFrame(frame.current), []);

  const replay = useCallback(() => run(0), [run]);

  const scrub = useCallback(
    (value: number) => {
      cancelAnimationFrame(frame.current);
      setPlaying(false);
      setProgress(value);
    },
    []
  );

  const toggle = useCallback(() => {
    if (playing) stop();
    else run(progress >= 1 ? 0 : progress);
  }, [playing, progress, run, stop]);

  return { progress, playing, replay, scrub, toggle };
};
