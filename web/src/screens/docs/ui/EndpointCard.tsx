import { useState } from "react";
import type { Endpoint } from "../model/endpoints";

type Live = { state: "idle" } | { state: "wait" } | { state: "done"; body: string; ok: boolean };

const probe = async (path: string): Promise<Live> => {
  try {
    const response = await fetch(`/api${path}`);
    const text = await response.text();
    const body = (() => {
      try {
        return JSON.stringify(JSON.parse(text), null, 2);
      } catch {
        return text.slice(0, 1200);
      }
    })();
    return { state: "done", body, ok: response.ok };
  } catch (error) {
    return { state: "done", body: `сервис недоступен: ${(error as Error).message}`, ok: false };
  }
};

export const EndpointCard = ({ endpoint }: { endpoint: Endpoint }) => {
  const [live, setLive] = useState<Live>({ state: "idle" });

  const run = async () => {
    if (!endpoint.probe) return;
    setLive({ state: "wait" });
    setLive(await probe(endpoint.probe));
  };

  return (
    <article className="ep" id={`ep-${endpoint.id}`}>
      <h3 className="ep-head">
        <span className="ep-method" data-method={endpoint.method}>
          {endpoint.method}
        </span>
        <span className="ep-path mono">{endpoint.path}</span>
      </h3>

      <p className="ep-what">{endpoint.what}</p>

      {endpoint.request ? (
        <pre className="ep-code scroll-x" tabIndex={0}>
          <code>{endpoint.request}</code>
        </pre>
      ) : null}

      <div className="ep-answer">
        <div className="ep-answer-bar">
          <span className="label">{live.state === "done" ? "ответ сервиса сейчас" : "ответ"}</span>
          {endpoint.probe ? (
            <button type="button" className="btn btn-ghost ep-run" onClick={run} disabled={live.state === "wait"}>
              {live.state === "wait" ? "запрашиваем…" : "выполнить"}
            </button>
          ) : null}
        </div>
        <pre className="ep-code scroll-x" tabIndex={0} data-live={live.state === "done"} data-bad={live.state === "done" && !live.ok}>
          <code>{live.state === "done" ? live.body : endpoint.response}</code>
        </pre>
      </div>

      {endpoint.errors ? (
        <dl className="ep-errors">
          {endpoint.errors.map(([code, when]) => (
            <div key={code}>
              <dt className="mono">{code}</dt>
              <dd>{when}</dd>
            </div>
          ))}
        </dl>
      ) : null}
    </article>
  );
};
