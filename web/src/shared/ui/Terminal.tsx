import { useCallback, useEffect, useRef, useState } from "react";

export interface Take {
  id: string;
  command: string;
  about: string;
  lines: string[];
}

const TYPE_MS = 14;
const LINE_MS = 42;

const useReplay = (take: Take) => {
  const [typed, setTyped] = useState(take.command.length);
  const [shown, setShown] = useState(take.lines.length);
  const timers = useRef<number[]>([]);

  const stop = useCallback(() => {
    timers.current.forEach((id) => window.clearTimeout(id));
    timers.current = [];
  }, []);

  useEffect(() => stop, [stop]);

  const replay = useCallback(() => {
    stop();
    setTyped(0);
    setShown(0);

    const plan = (delay: number, run: () => void) =>
      timers.current.push(window.setTimeout(run, delay));

    for (let i = 1; i <= take.command.length; i += 1) plan(i * TYPE_MS, () => setTyped(i));

    const after = take.command.length * TYPE_MS + 200;
    for (let i = 1; i <= take.lines.length; i += 1) plan(after + i * LINE_MS, () => setShown(i));
  }, [take, stop]);

  const running = typed < take.command.length || shown < take.lines.length;
  return { typed, shown, replay, running };
};

export const Terminal = ({ take }: { take: Take }) => {
  const { typed, shown, replay, running } = useReplay(take);

  return (
    <figure className="term">
      <figcaption className="term-about">{take.about}</figcaption>

      <div className="term-body">
        <div className="term-bar">
          <code className="term-cmd">
            <span className="term-prompt" aria-hidden="true">
              $
            </span>{" "}
            {take.command.slice(0, typed)}
            {running && typed < take.command.length ? <span className="term-caret" /> : null}
          </code>
          <button type="button" className="btn btn-ghost term-replay" onClick={replay} disabled={running}>
            {running ? "идёт…" : "повторить"}
          </button>
        </div>

        <pre className="term-out scroll-x" tabIndex={0}>
          {take.lines.slice(0, shown).map((line, index) => (
            <span key={index} className="term-line" data-warn={line.trimStart().startsWith("!")}>
              {line || " "}
            </span>
          ))}
        </pre>
      </div>
    </figure>
  );
};
