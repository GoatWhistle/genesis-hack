import { useEffect, useState } from "react";
import { buildZip, saveBlob, type ZipEntry } from "~/shared/model/zip";
import "./download.css";

type State = "ready" | "done" | "failed";

const entriesOf = (files: Record<string, string>): ZipEntry[] =>
  Object.entries(files).map(([name, content]) => ({ name, content }));

const totalBytes = (entries: ZipEntry[]) => {
  const encoder = new TextEncoder();
  return entries.reduce((sum, entry) => sum + encoder.encode(entry.content).length, 0);
};

const readableSize = (bytes: number) =>
  bytes < 1024 ? `${bytes} Б` : `${(bytes / 1024).toFixed(1).replace(".", ",")} КБ`;

const fileWord = (count: number) => {
  const tail = count % 100;
  if (tail >= 11 && tail <= 14) return "файлов";
  const last = count % 10;
  if (last === 1) return "файл";
  if (last >= 2 && last <= 4) return "файла";
  return "файлов";
};

interface DownloadRunProps {
  files: Record<string, string>;
  provider: string;
  contract: string;
}

export const DownloadRun = ({ files, provider, contract }: DownloadRunProps) => {
  const [state, setState] = useState<State>("ready");
  const entries = entriesOf(files);

  useEffect(() => {
    if (state === "ready") return;
    const timer = window.setTimeout(() => setState("ready"), 2400);
    return () => window.clearTimeout(timer);
  }, [state]);

  if (entries.length === 0) return null;

  const archive = `${provider}-${contract}.zip`;

  const download = () => {
    try {
      saveBlob(buildZip(entries), archive);
      setState("done");
    } catch {
      setState("failed");
    }
  };

  return (
    <span className="dl">
      <button
        type="button"
        className="btn btn-ghost dl-btn"
        onClick={download}
        title={`Собрать ${archive}`}
      >
        {state === "done" ? "Архив собран" : state === "failed" ? "Не собрался" : "Скачать всё"}
      </button>
      <span className="dl-hint mono">
        {entries.length} {fileWord(entries.length)}, {readableSize(totalBytes(entries))}
      </span>
    </span>
  );
};
