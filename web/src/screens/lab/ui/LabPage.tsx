import { useEffect, useMemo, useState } from "react";
import type { ContractProfile, Report } from "~/shared/api/types";
import type { PageProps } from "~/layout/types";
import { fetchContracts } from "~/shared/api/client";
import { useLiveBuild } from "~/shared/api/useRun";
import { defaultContract, profiles as bakedProfiles } from "~/shared/api/runs";
import { LabLive } from "./LabLive";
import { LabStep } from "./LabStep";
import { StepParse } from "./StepParse";
import { StepRoles } from "./StepRoles";
import { StepStatuses } from "./StepStatuses";
import { StepPlans } from "./StepPlans";
import { StepCode } from "./StepCode";
import { LabWarnings } from "./LabWarnings";
import { Pipeline } from "./Pipeline";
import { buildProvenance } from "../model/provenance";
import { methodNames } from "../model/methodNames";
import { looksOffline } from "../model/liveSource";
import { ProvenanceContext, useProvenanceState } from "./useProvenance";
import "./lab.css";

const emptyReport: Report = {
  provider: "",
  contract: "",
  spec: "",
  api: "",
  base_url: null,
  roles: {},
  statuses: {},
  events: {},
  amount: { multiplier: 1, note: "" },
  conditions: [],
  callback: { supported: false },
  auth: { primary: null, alternatives: [], notes: [] },
  warnings: []
};

const rubyFile = (files: Record<string, string>) =>
  Object.keys(files).find((name) => name.endsWith(".rb")) ?? "";

const selectedContract = () => sessionStorage.getItem("rsocket:selected-contract") ?? defaultContract;

const Lab = ({ go }: PageProps) => {
  const live = useLiveBuild();

  const [spec, setSpec] = useState("");
  const [provider, setProvider] = useState("");
  const [contract, setContract] = useState(selectedContract);
  const [profiles, setProfiles] = useState<ContractProfile[]>(bakedProfiles);
  const run = live.run;
  const shownProvider = run?.report.provider ?? provider;
  const shownContract = run?.report.contract ?? contract;

  useEffect(() => {
    void fetchContracts()
      .then((loaded) => {
        setProfiles(loaded);
        setContract((current) =>
          loaded.some((profile) => profile.name === current)
            ? current
            : loaded.find((profile) => profile.default)?.name ?? loaded[0]?.name ?? defaultContract
        );
      })
      .catch(() => undefined);
  }, []);

  const traced = run ? rubyFile(run.files) : "";
  const code = (run && traced ? run.files[traced] : "") ?? "";

  const map = useMemo(
    () => buildProvenance(run?.report ?? emptyReport, code, methodNames(shownContract)),
    [run, code, shownContract]
  );

  const link = useProvenanceState(map);
  const [stage, setStage] = useState("");
  const send = () => {
    setStage("");
    void live.send(spec, provider.trim(), contract);
  };

  return (
    <ProvenanceContext value={link}>
      <div className="shell-wide band-tight">
        <div className="lab-open-say">
          <h1 className="lab-title">Разобрать свой OpenAPI</h1>
          <p className="lab-lead">
            Укажите имя провайдера, выберите целевой контракт и вставьте описание в YAML или JSON.
            После запуска здесь появятся принятые решения и готовый код интеграции.
          </p>
        </div>
      </div>

      <div className="shell-wide">
        <LabLive
          provider={provider}
          contract={contract}
          profiles={profiles}
          spec={spec}
          loading={live.loading}
          error={live.error}
          offline={looksOffline(live.error)}
          onProvider={setProvider}
          onContract={setContract}
          onUploadContract={() => go("/rules", "?r=upload")}
          onSpec={setSpec}
          onSend={send}
        />
      </div>

      <div className="shell-wide lab-body">
        {run ? (
          <>
            <div className="lab-result-open">
              <p className="lab-badge" role="status">
                <span className="chip chip-provider">разбор готов</span>
                <code className="mono">{run.report.provider}</code>
                <span aria-hidden="true">→</span>
                <code className="mono">{run.report.contract}</code>
              </p>
              <Pipeline onStage={setStage} />
            </div>

            <LabWarnings warnings={run.warnings} />

            <LabStep no={1} stage={stage} title="Разбор" note={`${run.report.api}`}>
              <StepParse report={run.report} />
            </LabStep>

            <LabStep no={2} stage={stage} title="Раздача ролей" note="счёт, порог, правила">
              <StepRoles report={run.report} contract={shownContract} />
            </LabStep>

            <LabStep no={3} stage={stage} title="Статусы" note="слова провайдера → состояния контракта">
              <StepStatuses report={run.report} />
            </LabStep>

            <LabStep
              no={4}
              stage={stage}
              title="Сумма, ограничения, авторизация, уведомления"
              note="и откуда взято"
            >
              <StepPlans report={run.report} />
            </LabStep>

            <LabStep
              no={5}
              stage={stage}
              title="Код"
              note={`объяснено ${map.explained} строк кода из ${map.total}, пустые не в счёт`}
            >
              <StepCode
                files={run.files}
                contract={shownContract}
                provider={shownProvider}
                traced={traced}
              />
            </LabStep>
          </>
        ) : null}
      </div>
    </ProvenanceContext>
  );
};

export default Lab;
