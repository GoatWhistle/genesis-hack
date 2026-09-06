import { useId, useState } from "react";
import { useAllRuns } from "~/shared/api/useRuns";
import { amountShape, confusionFactor, rublesLabel, wireValue } from "../model/amount";

const STEPS = [100, 500, 1500, 5000, 25000, 100000];

export const AmountBoard = () => {
  const [index, setIndex] = useState(2);
  const runs = useAllRuns("space_payments");
  const sliderId = useId();

  const rubles = STEPS[index] ?? 1500;
  const shapes = runs.map(amountShape);
  const factor = shapes.length > 0 ? confusionFactor(shapes) : 100;

  return (
    <section className="board">
      <div className="shell-wide board-top">
        <h2 className="board-title">
          Одна сумма — четыре разных числа в теле запроса
        </h2>
        <label className="board-slider" htmlFor={sliderId}>
          <span className="label">заказчик просит перевести</span>
          <input
            id={sliderId}
            type="range"
            min={0}
            max={STEPS.length - 1}
            step={1}
            value={index}
            onChange={(event) => setIndex(Number(event.target.value))}
            aria-label="Сумма перевода"
            aria-valuetext={rublesLabel(rubles)}
          />
          <output className="board-amount" htmlFor={sliderId}>
            {rublesLabel(rubles)}
          </output>
        </label>
      </div>

      <div className="board-wire">
        {shapes.map((shape) => (
          <div className="board-cell" key={shape.provider}>
            <span className="board-provider">{shape.provider}</span>
            <span className="board-key mono">&quot;{shape.field}&quot;:</span>
            <span className="board-number">{wireValue(shape, rubles)}</span>
            <span className="board-units">
              {shape.type} · {shape.units}
              {shape.multiplier === 1 ? "" : ` · ×${shape.multiplier}`}
            </span>
          </div>
        ))}
      </div>

      <p className="shell-wide board-note">
        Между копейками и рублями множитель {factor}. Перепутать единицы — отправить в {factor} раз
        больше или меньше, чем просил заказчик, и узнать об этом от провайдера, а не от кода.
        Множитель читается из описания — <span className="mono">minimum</span>, тип поля, формат
        примера — и печатается в отчёт.
      </p>
    </section>
  );
};
