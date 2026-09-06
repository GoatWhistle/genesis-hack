import type { ProvenanceSource } from "../model/provenance";
import { lineWord } from "./useProvenance";

const KIND_LABEL: Record<ProvenanceSource["kind"], string> = {
  role: "решение о роли",
  condition: "ограничение из описания",
  status: "словарь состояний",
  event: "словарь событий",
  amount: "разбор суммы",
  callback: "уведомления",
  auth: "авторизация",
  base_url: "адрес провайдера"
};

interface ProvenanceNoteProps {
  source?: ProvenanceSource;
  count: number;
}

export const ProvenanceNote = ({ source, count }: ProvenanceNoteProps) => {
  if (!source) {
    return (
      <div className="lab-note lab-note-idle">
        <p className="label">Откуда эта строка</p>
        <p>
          Строки с чертой слева пришли из разбора. Наведите на любую — здесь появится решение,
          которое её породило. Обратно тоже работает: наведите на роль в шаге 2.
        </p>
      </div>
    );
  }

  return (
    <div className={`lab-note lab-note-${source.side}`}>
      <p className="label">{KIND_LABEL[source.kind]}</p>
      <p className="lab-note-title">{source.title}</p>
      <p className="lab-note-summary">{source.summary}</p>
      {source.details.length > 0 ? (
        <ul className="lab-note-details">
          {source.details.map((detail) => (
            <li key={detail}>{detail}</li>
          ))}
        </ul>
      ) : null}
      <p className="lab-note-count mono">
        {count} {lineWord(count)} в файле
      </p>
    </div>
  );
};
