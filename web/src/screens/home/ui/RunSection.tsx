import { useState } from "react";
import { CopyIcon } from "~/shared/design/CopyIcon";

const WAYS = [
  {
    title: "Через публичный API",
    command:
      'curl -X POST "https://genesis.goatwhistle.ru/api/build?provider=novapay&contract=space_payments" -H "Content-Type: application/yaml" --data-binary @examples/novapay/provider_api.yaml'
  },
  {
    title: "Локально из репозитория",
    command:
      "bundle exec bin/rsocket build -s examples/novapay/provider_api.yaml -p novapay -c space_payments"
  }
];

const CopyButton = ({ text }: { text: string }) => {
  const [done, setDone] = useState(false);

  const copy = () => {
    void navigator.clipboard.writeText(text).then(() => {
      setDone(true);
      setTimeout(() => setDone(false), 1600);
    });
  };

  return (
    <button
      type="button"
      className="btn btn-ghost btn-icon"
      onClick={copy}
      aria-label={done ? "Скопировано" : "Скопировать команду"}
      title={done ? "Скопировано" : "Скопировать команду"}
    >
      <CopyIcon size={18} done={done} />
    </button>
  );
};

export const RunSection = () => (
  <section className="shell-wide band-tight ways">
    <h2 className="ways-title">Два пути к одному результату</h2>
    <div className="ways-list">
      {WAYS.map((way) => (
        <div className="run-item" key={way.title}>
          <span className="run-title">{way.title}</span>
          <div className="run-cmd">
            <pre>{way.command}</pre>
            <CopyButton text={way.command} />
          </div>
        </div>
      ))}
    </div>
  </section>
);
