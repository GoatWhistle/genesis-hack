import { useEffect, useRef, useState } from "react";
import { parse } from "yaml";
import type { PageProps } from "~/layout/types";
import type { ContractProfile } from "~/shared/api/types";
import { fetchContracts, readRule, writeRule } from "~/shared/api/client";
import { defaultContract, profiles as bakedProfiles } from "~/shared/api/runs";
import { ArrowRight } from "~/shared/design/ArrowRight";
import { SwitchTabs } from "~/shared/ui/SwitchTabs";

const CONTRACT_SELECTION_KEY = "rsocket:selected-contract";
const validName = /^[a-z0-9][a-z0-9_-]*$/;

interface UploadedContract {
  contract?: {
    outputs?: { template?: unknown }[];
  };
}

const templatesIn = (source: string): string[] => {
  const document = parse(source) as UploadedContract | null;
  const outputs = document?.contract?.outputs;
  if (!Array.isArray(outputs) || outputs.length === 0) {
    throw new Error("В contract.yml не найден список contract.outputs.");
  }

  const templates = outputs.map((output) => output?.template);
  if (templates.some((template) => typeof template !== "string" || template.trim() === "")) {
    throw new Error("У каждого элемента contract.outputs должен быть указан template.");
  }

  return [...new Set(templates as string[])];
};

export const ContractUpload = ({ go }: PageProps) => {
  const [name, setName] = useState("");
  const [base, setBase] = useState(defaultContract);
  const [source, setSource] = useState("");
  const [profiles, setProfiles] = useState<ContractProfile[]>(bakedProfiles);
  const [fileName, setFileName] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    void fetchContracts()
      .then((loaded) => {
        setProfiles(loaded);
        setBase((current) =>
          loaded.some((profile) => profile.name === current)
            ? current
            : loaded.find((profile) => profile.default)?.name ?? loaded[0]?.name ?? defaultContract
        );
      })
      .catch(() => undefined);
  }, []);

  const pickFile = async (file: File) => {
    setError("");
    setSaved("");
    setFileName(file.name);
    setSource(await file.text());
  };

  const save = async () => {
    const normalized = name.trim().toLowerCase();
    setError("");
    setSaved("");

    if (!validName.test(normalized)) {
      setError("Имя должно начинаться с буквы или цифры и содержать только a–z, 0–9, _ или -.");
      return;
    }
    if (profiles.some((profile) => profile.name === normalized)) {
      setError("Контракт с таким именем уже существует — существующие профили здесь не перезаписываются.");
      return;
    }
    if (!source.trim()) {
      setError("Выберите файл contract.yml.");
      return;
    }

    try {
      const requiredTemplates = templatesIn(source);
      const templateProfile = profiles.find((profile) => profile.name === base);
      const available = new Set(templateProfile?.files ?? []);
      const missing = requiredTemplates.filter((template) => !available.has(template));
      if (missing.length > 0) {
        throw new Error(`В профиле ${base} нет шаблонов: ${missing.join(", ")}.`);
      }

      setSaving(true);
      const templates = await Promise.all(
        requiredTemplates.map(async (template) => ({
          template,
          content: (await readRule(`contracts/${base}/${template}`)).content
        }))
      );
      await Promise.all(
        templates.map(({ template, content }) =>
          writeRule(`contracts/${normalized}/${template}`, content)
        )
      );
      await writeRule(`contracts/${normalized}/contract.yml`, source);
      sessionStorage.setItem(CONTRACT_SELECTION_KEY, normalized);
      setSaved(normalized);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Не удалось загрузить контракт.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="contract-upload">
      <p className="prose-column rls-lead">
        Загрузите только <code className="mono">contract.yml</code>. Шаблоны генерации останутся
        теми, что уже загружены в сервис: выберите существующий профиль, чей комплект нужно
        переиспользовать.
      </p>

      <div className="contract-upload-form">
        <label className="contract-upload-field">
          <span className="label">Имя нового контракта</span>
          <input
            className="contract-upload-input mono"
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="my_contract"
            spellCheck={false}
          />
        </label>

        <div className="contract-upload-field">
          <span className="label">Использовать шаблоны профиля</span>
          <SwitchTabs
            label="Профиль шаблонов"
            group="contract-base"
            role="group"
            options={profiles.map((profile) => ({
              id: profile.name,
              label: profile.name,
              title: profile.title
            }))}
            current={base}
            onPick={setBase}
          />
        </div>

        <div className="contract-upload-filebox">
          <div>
            <strong>{fileName || "contract.yml"}</strong>
            <span>{source ? `${source.length} символов прочитано` : "YAML, один файл"}</span>
          </div>
          <button type="button" className="btn btn-ghost" onClick={() => fileRef.current?.click()}>
            {source ? "Выбрать другой" : "Выбрать contract.yml"}
          </button>
          <input
            ref={fileRef}
            className="contract-upload-hidden"
            type="file"
            accept=".yml,.yaml,application/yaml,text/yaml"
            aria-label="Файл contract.yml"
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (file) void pickFile(file);
            }}
          />
        </div>

        <div className="contract-upload-actions">
          <button
            type="button"
            className="btn btn-primary"
            disabled={saving || !source || !name.trim()}
            onClick={() => void save()}
          >
            {saving ? "Загружаем…" : "Загрузить контракт"}
          </button>
          <span>contract.yml + шаблоны из {base}</span>
        </div>
      </div>

      {error ? (
        <p className="notice contract-upload-notice" role="alert">
          <span className="notice-mark">!</span>
          {error}
        </p>
      ) : null}

      {saved ? (
        <div className="contract-upload-success" role="status">
          <div>
            <span className="chip chip-contract">контракт загружен</span>
            <strong className="mono">{saved}</strong>
          </div>
          <button type="button" className="btn btn-primary" onClick={() => go("/lab")}>
            Разобрать документ с этим контрактом
            <ArrowRight size={14} />
          </button>
        </div>
      ) : null}
    </div>
  );
};
