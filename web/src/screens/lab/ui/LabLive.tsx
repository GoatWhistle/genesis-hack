import { useRef, useState } from "react";
import type { ContractProfile } from "~/shared/api/types";

interface LabLiveProps {
  provider: string;
  contract: string;
  profiles: ContractProfile[];
  spec: string;
  loading: boolean;
  error: string | undefined;
  offline: boolean;
  onProvider: (value: string) => void;
  onContract: (value: string) => void;
  onUploadContract: () => void;
  onSpec: (value: string) => void;
  onSend: () => void;
}

const readDropped = (file: File, onSpec: (value: string) => void) => {
  const reader = new FileReader();
  reader.onload = () => onSpec(String(reader.result ?? ""));
  reader.readAsText(file);
};

export const LabLive = ({
  provider,
  contract,
  profiles,
  spec,
  loading,
  error,
  offline,
  onProvider,
  onContract,
  onUploadContract,
  onSpec,
  onSend
}: LabLiveProps) => {
  const [over, setOver] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const noProvider = provider.trim() === "";
  const noSpec = spec.trim() === "";
  const missing = noProvider && noSpec
    ? "впишите имя провайдера и вставьте описание"
    : noProvider
      ? "впишите имя провайдера — оно станет именем класса"
      : noSpec
        ? "вставьте описание или выберите файл"
        : "";

  return (
    <div className="lab-live">
      <div className="lab-live-row">
        <label className="lab-live-field">
          <span className="label">Имя провайдера</span>
          <input
            className="lab-live-input mono"
            value={provider}
            onChange={(event) => onProvider(event.target.value)}
            placeholder="swiftpay"
            spellCheck={false}
          />
        </label>

        <div className="lab-live-field">
          <span className="label">Контракт</span>
          <div className="lab-contract-row">
            <div className="switch" role="group" aria-label="Контракт">
              {profiles.map((profile) => (
                <button
                  key={profile.name}
                  type="button"
                  className="switch-item mono"
                  aria-pressed={profile.name === contract}
                  title={profile.title}
                  onClick={() => onContract(profile.name)}
                >
                  {profile.name}
                </button>
              ))}
            </div>
            <button type="button" className="btn btn-ghost" onClick={onUploadContract}>
              + Загрузить контракт
            </button>
          </div>
        </div>
      </div>

      <div
        className="lab-live-drop"
        data-over={over}
        onDragOver={(event) => {
          event.preventDefault();
          setOver(true);
        }}
        onDragLeave={() => setOver(false)}
        onDrop={(event) => {
          event.preventDefault();
          setOver(false);
          const file = event.dataTransfer.files[0];
          if (file) readDropped(file, onSpec);
        }}
      >
        <label className="lab-live-label" htmlFor="lab-live-spec">
          Описание OpenAPI провайдера — YAML или JSON
        </label>
        <textarea
          id="lab-live-spec"
          className="lab-live-area mono"
          value={spec}
          onChange={(event) => onSpec(event.target.value)}
          placeholder="Вставьте описание сюда или перетащите файл на эту область"
          spellCheck={false}
        />
        <div className="lab-live-actions">
          <button
            type="button"
            className="btn btn-primary"
            disabled={loading || noSpec || noProvider}
            onClick={onSend}
          >
            {loading ? "Разбираем…" : "Разобрать"}
          </button>
          {missing && !loading ? <span className="lab-live-missing">{missing}</span> : null}
          <button type="button" className="btn btn-ghost" onClick={() => fileRef.current?.click()}>
            Выбрать файл
          </button>
          <input
            ref={fileRef}
            className="lab-live-file"
            type="file"
            aria-label="Файл с описанием OpenAPI"
            accept=".yaml,.yml,.json,.txt"
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (file) readDropped(file, onSpec);
            }}
          />
        </div>
      </div>

      {error ? (
        <p className="notice lab-live-error" role="alert">
          <span className="notice-mark" aria-hidden="true">
            !
          </span>
          <span>
            {offline ? (
              <>
                Живой режим требует запущенного сервиса — сейчас он не отвечает. Поднимите его
                командой <code className="mono">docker compose up</code> в корне репозитория и
                повторите разбор.
              </>
            ) : (
              error
            )}
          </span>
        </p>
      ) : null}
    </div>
  );
};
