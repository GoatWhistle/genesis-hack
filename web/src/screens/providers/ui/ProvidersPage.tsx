import { useMemo } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { PageProps } from "~/layout/types";
import { useSearchParam } from "~/layout/useRoute";
import { providers, defaultContract } from "~/shared/api/runs";
import { compareRows, orderProviders } from "../model/compare";
import { CompareTable } from "./CompareTable";
import { ProviderReport } from "./ProviderReport";
import { FileTabs } from "~/shared/ui/FileTabs";
import { DownloadRun } from "~/shared/ui/DownloadRun";
import { useRunsByProvider } from "~/shared/api/useRuns";
import { SwitchTabs } from "~/shared/ui/SwitchTabs";
import { enterVariants, useSwapTransition } from "~/shared/lib/motion";
import "./providers.css";

const ORDERED = orderProviders(providers);
const FIRST = ORDERED[0] ?? "novapay";

const isKnownProvider = (value: string) => ORDERED.includes(value);

const Providers = (_props: PageProps) => {
  const [open, setOpen] = useSearchParam("provider", FIRST, isKnownProvider);
  const { runs, error } = useRunsByProvider(defaultContract);
  const rows = useMemo(() => compareRows(runs), [runs]);

  const current = ORDERED.includes(open) ? open : FIRST;
  const run = runs[current];
  const swap = useSwapTransition();

  return (
    <div className="band">
      <header className="shell-wide prv-head">
        <h1>Четыре описания</h1>
        <p className="prose-column">
          Их писали разные люди в разных банках и ни разу не сговаривались. Сумма то в
          копейках, то дробным числом, то строкой; создание называется{" "}
          <span className="mono side-provider">createPayout</span>,{" "}
          <span className="mono side-provider">submitTransfer</span>,{" "}
          <span className="mono side-provider">makeTransfer</span> и{" "}
          <span className="mono side-provider">createPaymentOrder</span>. Инструмент собрал
          все четыре по одним и тем же правилам и честно назвал, чего не понял.
        </p>
      </header>

      {error ? (
        <p className="shell-wide notice">
          <span className="notice-mark" aria-hidden="true">
            !
          </span>
          <span>
            Запечённые прогоны не открылись — сравнение показано по тем, что уже были загружены.
            Обновите страницу; сами разборы лежат в сборке сайта и сервер для них не нужен.
          </span>
        </p>
      ) : null}

      <section className="shell-wide band-tight" aria-labelledby="cmp-h">
        <h2 id="cmp-h" className="prv-h2">
          Где они расходятся
        </h2>
        <p className="prose-column prv-lead">
          Шесть признаков в строках, четыре описания в колонках. Читать построчно: одна строка —
          одно решение, которое инструмент принял по каждому провайдеру. Расхождения крупные:
          сумма приходит в копейках у двоих и в рублях у двоих, слов о состоянии платежа четыре
          или пять, а сводятся они к трём статусам контракта; webhook описан только у{" "}
          <span className="mono">novapay</span> — у остальных трёх роль{" "}
          <span className="mono side-contract">process_callback</span> осталась заглушкой.
        </p>
        <CompareTable providers={ORDERED} rows={rows} active={current} onPick={setOpen} />
        <p className="cmp-legend">
          <span className="cmp-legend-mark" aria-hidden="true" /> отмечено то, что выбивается из
          общего ряда и требует внимания человека. Колонку можно выбрать — ниже раскроется её
          разбор.
        </p>
      </section>

      <section className="shell-wide band-tight rule-line" aria-labelledby="one-h">
        <div className="prv-picker">
          <h2 id="one-h" className="prv-h2">
            Разбор целиком
          </h2>
          <SwitchTabs
            label="Провайдер"
            group="providers-pick"
            options={ORDERED.map((provider) => ({ id: provider, label: provider }))}
            current={current}
            onPick={setOpen}
          />
        </div>

        {run ? (
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={current}
              variants={enterVariants}
              initial="hidden"
              animate="shown"
              exit="gone"
              transition={swap}
            >
              <p className="prv-api">
                <span className="chip chip-provider">{run.report.api}</span>
                <span className="mono cmp-hint">{run.report.base_url ?? "адрес не указан"}</span>
              </p>
              <ProviderReport report={run.report} />
              <div className="prv-files">
                <div className="prv-files-head">
                  <h3 className="label">Что собралось</h3>
                  <DownloadRun files={run.files} provider={current} contract={defaultContract} />
                </div>
                <FileTabs files={run.files} />
              </div>
            </motion.div>
          </AnimatePresence>
        ) : (
          <p className="label">
            {error ? `Разбор ${current} не открылся — выберите другого провайдера` : "Загружаем прогоны…"}
          </p>
        )}
      </section>
    </div>
  );
};

export default Providers;
