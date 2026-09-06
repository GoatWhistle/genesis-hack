import { useState } from "react";

const WAYS = [
  {
    title: "По HTTP",
    about: "сервис уже поднят на 9292 — описание уходит телом запроса",
    command:
      'curl -X POST "http://127.0.0.1:9292/build?provider=novapay" --data-binary @examples/novapay/provider_api.yaml'
  },
  {
    title: "Из командной строки",
    about: "то же самое без сервиса, результат ложится в каталог сборки",
    command: "bundle exec bin/rsocket build -s examples/novapay/provider_api.yaml -p novapay"
  },
  {
    title: "Всё вместе",
    about: "сервис, хранилище правил и S3-совместимое хранилище одним запуском",
    command: "docker compose up"
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
    <button type="button" className="btn btn-ghost" onClick={copy} aria-label="Скопировать команду">
      {done ? "Скопировано" : "Копировать"}
    </button>
  );
};

export const RunSection = () => (
  <section className="shell-wide band-tight ways">
    <h2 className="ways-title">Три пути к одному результату</h2>
    <div className="ways-list">
      {WAYS.map((way) => (
        <div className="run-item" key={way.title}>
          <div className="run-top">
            <span className="run-title">{way.title}</span>
            <span className="home-note">{way.about}</span>
          </div>
          <div className="run-cmd">
            <pre>{way.command}</pre>
            <CopyButton text={way.command} />
          </div>
        </div>
      ))}
    </div>
  </section>
);
