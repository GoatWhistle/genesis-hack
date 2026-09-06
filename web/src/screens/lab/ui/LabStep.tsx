import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { stageOfStep } from "../model/stages";

interface LabStepProps {
  no: number;
  title: string;
  note?: string;
  stage: string;
  children: ReactNode;
}

export const LabStep = ({ no, title, note, stage, children }: LabStepProps) => {
  const [folded, setFolded] = useState(false);
  const bodyId = useId();
  const ref = useRef<HTMLElement>(null);
  const marked = Boolean(stage) && stageOfStep(no)?.id === stage;
  const open = marked || !folded;

  useEffect(() => {
    if (marked) ref.current?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [marked]);

  return (
    <section className="lab-step" ref={ref} data-marked={marked}>
      <h3>
        <button
          type="button"
          className="lab-step-head"
          aria-expanded={open}
          aria-controls={bodyId}
          onClick={() => setFolded(open)}
        >
          <span className="lab-step-no">{`0${no}`}</span>
          <span className="lab-step-title">{title}</span>
          {note ? <span className="lab-step-note">{note}</span> : null}
          <span className="lab-step-sign" aria-hidden="true">
            {open ? "−" : "+"}
          </span>
        </button>
      </h3>
      <div id={bodyId} className="lab-step-body" hidden={!open}>
        {children}
      </div>
    </section>
  );
};
