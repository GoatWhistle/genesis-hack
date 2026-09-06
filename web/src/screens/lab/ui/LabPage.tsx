import { useMemo, useState } from "react";
import type { Report } from "~/shared/api/types";
import type { PageProps } from "~/layout/types";
import { useSearchParam } from "~/layout/useRoute";
import { useBakedRun, useLiveBuild } from "~/shared/api/useRun";
import { defaultContract, defaultProvider, contractNames, providers } from "~/shared/api/runs";
import { LabInput } from "./LabInput";
import { LabLive } from "./LabLive";
import { LabSourcePick } from "./LabSourcePick";
import { LabStep } from "./LabStep";
import { StepParse } from "./StepParse";
import { StepRoles } from "./StepRoles";
import { StepStatuses } from "./StepStatuses";
import { StepPlans } from "./StepPlans";
import { StepCode } from "./StepCode";
import { LabWarnings } from "./LabWarnings";
import { LabHistory } from "./LabHistory";
import { Pipeline } from "./Pipeline";
import { buildProvenance } from "../model/provenance";
import { methodNames } from "../model/methodNames";
import { isLabSource, looksOffline } from "../model/liveSource";
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

const isKnownProvider = (value: string) => providers.includes(value);
const isKnownContract = (value: string) => contractNames.includes(value);

const Lab = (_props: PageProps) => {
  const [provider, setProvider] = useSearchParam("provider", defaultProvider, isKnownProvider);
  const [contract, setContract] = useSearchParam("contract", defaultContract, isKnownContract);

  const safeProvider = isKnownProvider(provider) ? provider : defaultProvider;
  const safeContract = isKnownContract(contract) ? contract : defaultContract;

  const [rawSource, setSource] = useSearchParam("source", "baked", isLabSource);
  const source = isLabSource(rawSource) ? rawSource : "baked";

  const baked = useBakedRun(safeProvider, safeContract);
  const live = useLiveBuild();

  const [spec, setSpec] = useState("");
  const [liveProvider, setLiveProvider] = useState("");
  const [liveContract, setLiveContract] = useState(defaultContract);

  const isLive = source === "live";
  const run = isLive ? live.run : baked.run;
  const loading = isLive ? live.loading : baked.loading;
  const error = isLive ? undefined : baked.error;

  const shownProvider = isLive ? liveProvider : safeProvider;
  const shownContract = isLive ? liveContract : safeContract;

  const traced = run ? rubyFile(run.files) : "";
  const code = (run && traced ? run.files[traced] : "") ?? "";

  const map = useMemo(
    () => buildProvenance(run?.report ?? emptyReport, code, methodNames(shownContract)),
    [run, code, shownContract]
  );

  const link = useProvenanceState(map);
  const [stage, setStage] = useState("");

  const goToVisit = (nextProvider: string, nextContract: string) => {
    setProvider(nextProvider);
    setContract(nextContract);
  };

  return (
    <ProvenanceContext value={link}>
      <div className="shell-wide band-tight lab-open">
        <div className="lab-open-say">
          <h1 className="lab-title">Разбор описания</h1>
          <p className="lab-lead">
            Пять шагов ниже показывают, как из описания провайдера получается готовый код: операции,
            раздача ролей со счётом и порогом, словарь состояний, разбор суммы и авторизации, файлы.
            В последнем шаге каждая строка кода помнит, какое решение её породило.
          </p>
        </div>
        <Pipeline onStage={setStage} />
      </div>

      <div className="shell-wide lab-pick-bar">
        <LabSourcePick source={source} onPick={setSource} />
      </div>

      {isLive ? (
        <div className="shell-wide">
          <LabLive
            provider={liveProvider}
            contract={liveContract}
            spec={spec}
            loading={live.loading}
            error={live.error}
            offline={looksOffline(live.error)}
            onProvider={setLiveProvider}
            onContract={setLiveContract}
            onSpec={setSpec}
            onSend={() => void live.send(spec, liveProvider.trim(), liveContract)}
            onBaked={() => setSource("baked")}
          />
        </div>
      ) : (
        <LabInput
          provider={safeProvider}
          contract={safeContract}
          onProvider={setProvider}
          onContract={setContract}
          run={run}
        />
      )}

      <div className="shell-wide lab-body">

        {isLive ? null : (
          <LabHistory provider={safeProvider} contract={safeContract} onPick={goToVisit} />
        )}

        {error ? (
          <p className="notice lab-error" role="alert">
            <span className="notice-mark" aria-hidden="true">
              !
            </span>
            Прогон не загрузился: {error}
          </p>
        ) : null}

        {loading && !run ? (
          <p className="label band-tight" role="status">
            Загружаем прогон…
          </p>
        ) : null}

        {run ? (
          <>
            {isLive ? (
              <p className="lab-badge" role="status">
                <span className="chip chip-provider">живой разбор</span>
                Собрано сервисом только что: <code className="mono">POST /api/build</code> для{" "}
                <code className="mono">{run.report.provider}</code> по контракту{" "}
                <code className="mono">{run.report.contract}</code>. Это не запечённый прогон.
              </p>
            ) : null}

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
