import { useState } from "react";
import { useBakedRun } from "~/shared/api/useRun";
import { SlidingPlate } from "~/shared/ui/SlidingPlate";
import { useHighlight } from "~/shared/lib/useHighlight";

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

interface PaneProps {
  file: string;
  hint: string;
  code: string;
}

const TwinPane = ({ file, hint, code }: PaneProps) => {
  const html = useHighlight(code, "ruby");

  return (
    <div className="twin-pane">
      <p className="twin-file mono side-contract">{file}</p>
      <p className="twin-hint">{hint}</p>
      <div className="scroll-x" tabIndex={0} role="region" aria-label="Код метода, прокрутка вбок">
        {html ? (
          <div className="twin-pre" dangerouslySetInnerHTML={{ __html: html }} />
        ) : (
          <pre className="twin-pre">{code}</pre>
        )}
      </div>
    </div>
  );
};

export const TwinSection = () => {
  const [active, setActive] = useState(0);
  const [pickHost, setPickHost] = useState<HTMLDivElement | null>(null);
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
        <div className="twin-picker" role="group" aria-label="Роль контракта" ref={setPickHost}>
          <SlidingPlate host={pickHost} activeKey={String(active)} className="twin-pick-slider" />
          {PAIRS.map((item, index) => {
            const picked = index === active;

            return (
              <button
                type="button"
                className="twin-pick"
                key={item.role}
                aria-pressed={picked}
                data-active={picked}
                data-plate={picked}
                onClick={() => setActive(index)}
              >
                <span className="twin-pick-role">{item.role}</span>
                <span className="twin-pick-about">{item.about}</span>
              </button>
            );
          })}
        </div>
      </div>

      <div className="twin-code">
        <TwinPane
          file="novapay_service.rb"
          hint="отказ возвращается значением"
          code={methodBody(service.run.files["novapay_service.rb"] ?? "", pair.service)}
        />
        <TwinPane
          file="novapay_client.rb"
          hint="отказ бросается исключением"
          code={methodBody(client.run.files["novapay_client.rb"] ?? "", pair.client)}
        />
      </div>
    </section>
  );
};
