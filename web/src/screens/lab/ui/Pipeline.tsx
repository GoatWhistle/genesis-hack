import { useState } from "react";
import { STAGES } from "../model/stages";
import "./pipeline.css";

interface PipelineProps {
  onStage: (stageId: string) => void;
}

export const Pipeline = ({ onStage }: PipelineProps) => {
  const [open, setOpen] = useState("");
  const stage = STAGES.find((item) => item.id === open);

  const pick = (id: string) => {
    setOpen(id === open ? "" : id);
    onStage(id === open ? "" : id);
  };

  return (
    <section className="pipe" aria-labelledby="pipe-h">
      <div className="pipe-head">
        <h2 id="pipe-h" className="pipe-h">
          Шесть стадий сборки
        </h2>
        <p className="pipe-lead">
          Крайние две — откуда взялось описание и куда лёг результат; четыре средние раскладываются
          в пять шагов разбора ниже. Нажмите стадию, чтобы прочитать, что она делает, и перейти к её
          шагу.
        </p>
      </div>

      <ol className="pipe-flow">
        {STAGES.map((item) => (
          <li key={item.id}>
            <button
              type="button"
              className="pipe-node"
              aria-expanded={item.id === open}
              aria-controls="pipe-detail"
              onClick={() => pick(item.id)}
            >
              <span className="pipe-node-title">{item.title}</span>
              <span className="pipe-node-role mono">{item.role}</span>
              {item.steps ? (
                <span className="pipe-node-step mono">
                  шаг {item.steps.map((no) => `0${no}`).join(" и ")}
                </span>
              ) : (
                <span className="pipe-node-step pipe-node-edge">край</span>
              )}
            </button>
          </li>
        ))}
      </ol>

      <div id="pipe-detail" className="pipe-detail" hidden={!stage}>
        {stage ? (
          <>
            <div>
              <p className="pipe-what">{stage.what}</p>
              <p className="label pipe-files-label">Где искать в исходниках</p>
              <ul className="pipe-files">
                {stage.files.map((file) => (
                  <li key={file} className="chip chip-quiet">
                    app/{file}
                  </li>
                ))}
              </ul>
            </div>
            {stage.why ? <p className="pipe-why">{stage.why}</p> : null}
          </>
        ) : null}
      </div>
    </section>
  );
};
