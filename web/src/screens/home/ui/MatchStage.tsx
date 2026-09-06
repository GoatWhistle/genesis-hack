import { useId } from "react";
import type { PageProps } from "~/layout/types";
import { useBakedRun } from "~/shared/api/useRun";
import { beatWindow, stageBeats } from "../model/stage";
import { useChoreography } from "./useChoreography";
import { CodeColumn, OperationCard, RivalList, RuleList, ScoreMeter } from "./StageBeat";

const CONTRACT = "space_payments";
const DURATION = 8600;

const clamp01 = (value: number) => Math.min(1, Math.max(0, value));

export const MatchStage = ({ go }: PageProps) => {
  const { run } = useBakedRun("novapay", CONTRACT);
  const scrubId = useId();
  const beats = run ? stageBeats(run, CONTRACT) : [];
  const clock = useChoreography(DURATION, beats.length > 0);

  return (
    <section className="stage">
      <div className="shell-wide stage-inner">
        <header className="stage-head">
          <h1 className="stage-title">
            Описание <span className="side-provider">чужого API</span> становится{" "}
            <span className="side-contract">вашим классом</span> за один прогон
          </h1>
          <p className="stage-lead">
            Ниже это происходит на настоящих данных: операции{" "}
            <span className="mono side-provider">novapay</span> примеряются к ролям контракта{" "}
            <span className="mono side-contract">{CONTRACT}</span>, регулярки настоящие, счёт
            настоящий, код — тот, что уйдёт в репозиторий.
          </p>
        </header>

        <div className="stage-grid">
          {beats.map((beat, index) => {
            const { from, to } = beatWindow(index, beats.length);
            const local = clamp01((clock.progress - from) / (to - from));

            return (
              <article className="stage-beat" key={beat.role} data-live={local > 0 && local < 1}>
                <div className="stage-cell stage-cell-op">
                  <OperationCard beat={beat} local={local} />
                  <RivalList beat={beat} local={local} />
                </div>

                <div className="stage-cell stage-cell-rule">
                  <ScoreMeter beat={beat} local={local} />
                  <RuleList beat={beat} local={local} />
                </div>

                <div className="stage-cell stage-cell-role">
                  <p className="stage-role-name mono side-contract">{beat.role}</p>
                  <p className="stage-role-title">{beat.title}</p>
                  <CodeColumn beat={beat} local={local} />
                </div>
              </article>
            );
          })}
        </div>

        <div className="stage-controls">
          <button type="button" className="btn btn-ghost" onClick={clock.toggle}>
            {clock.playing ? "Пауза" : "Играть"}
          </button>
          <button type="button" className="btn btn-ghost" onClick={clock.replay}>
            Повторить
          </button>
          <label className="stage-scrub" htmlFor={scrubId}>
            <span className="label">Перемотка разбора</span>
            <input
              id={scrubId}
              type="range"
              min={0}
              max={1000}
              step={1}
              value={Math.round(clock.progress * 1000)}
              onChange={(event) => clock.scrub(Number(event.target.value) / 1000)}
              aria-valuetext={`${Math.round(clock.progress * 100)} процентов разбора`}
            />
          </label>
          <button type="button" className="btn btn-primary" onClick={() => go("/lab")}>
            Разобрать своё описание
          </button>
        </div>
      </div>
    </section>
  );
};
