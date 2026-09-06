import { useState } from "react";
import { useBakedRun } from "~/shared/api/useRun";

const PAIRS: { role: string; service: string; client: string; about: string }[] = [
  {
    role: "создание выплаты",
    service: "create_request",
    client: "send_payout",
    about: "одна и та же операция POST /payouts"
  },
  {
    role: "статус-запрос",
    service: "fetch_status",
    client: "payout_state",
    about: "одна и та же операция GET /payouts/{payout_id}"
  },
  {
    role: "отмена операции",
    service: "cancel_request",
    client: "cancel_payout",
    about: "одна и та же операция POST /payouts/{payout_id}/cancel"
  }
];

const methodBody = (file: string, name: string): string => {
  const lines = file.split("\n");
  const start = lines.findIndex((line) => new RegExp(`^\\s*def ${name}\\b`).test(line));
  if (start < 0) return "";

  const indent = lines[start]?.match(/^\s*/)?.[0].length ?? 0;
  let stop = start + 1;
  while (stop < lines.length) {
    const line = lines[stop] ?? "";
    if (line.trim() === "end" && (line.match(/^\s*/)?.[0].length ?? 0) === indent) break;
    stop += 1;
  }

  return lines
    .slice(start, stop + 1)
    .map((line) => line.slice(indent))
    .filter((line) => !line.trim().startsWith("#"))
    .join("\n");
};

export const TwinSection = () => {
  const [active, setActive] = useState(0);
  const service = useBakedRun("novapay", "space_payments");
  const client = useBakedRun("novapay", "plain_client");

  if (!service.run || !client.run) return null;

  const pair = PAIRS[active] ?? PAIRS[0];
  if (!pair) return null;

  return (
    <section className="shell-wide band twin">
      <div className="twin-ask">
        <h2 className="twin-title">Один разбор — два несовместимых класса</h2>
        <p className="twin-lead">
          Ни одна строка про NovaPay не поменялась. Поменялся профиль контракта — и вместе с ним
          имена методов и то, чем сообщается отказ.
        </p>
        <div className="twin-picker" role="group" aria-label="Роль контракта">
          {PAIRS.map((item, index) => (
            <button
              type="button"
              className="twin-pick"
              key={item.role}
              aria-pressed={index === active}
              data-active={index === active}
              onClick={() => setActive(index)}
            >
              <span className="twin-pick-role">{item.role}</span>
              <span className="twin-pick-about">{item.about}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="twin-code">
        <div className="twin-pane">
          <p className="twin-file mono side-contract">novapay_service.rb</p>
          <p className="twin-hint">отказ возвращается значением</p>
          <div className="scroll-x" tabIndex={0} role="region" aria-label="Код метода, прокрутка вбок">
            <pre className="twin-pre">{methodBody(service.run.files["novapay_service.rb"] ?? "", pair.service)}</pre>
          </div>
        </div>
        <div className="twin-pane">
          <p className="twin-file mono side-contract">novapay_client.rb</p>
          <p className="twin-hint">отказ бросается исключением</p>
          <div className="scroll-x" tabIndex={0} role="region" aria-label="Код метода, прокрутка вбок">
            <pre className="twin-pre">{methodBody(client.run.files["novapay_client.rb"] ?? "", pair.client)}</pre>
          </div>
        </div>
      </div>
    </section>
  );
};
