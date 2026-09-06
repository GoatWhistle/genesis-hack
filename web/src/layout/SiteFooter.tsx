import { bakedAt, contractNames, providers } from "~/shared/api/runs";
import { GithubLink } from "~/shared/design/GithubLink";
import type { PageProps } from "./types";

const dayAndMonth = new Date(bakedAt).toLocaleDateString("ru-RU", {
  day: "numeric",
  month: "long"
});
const yearWithoutAbbreviation = new Date(bakedAt).getFullYear();

export const SiteFooter = ({ go }: PageProps) => (
  <footer className="rule-line">
    <div className="shell-wide band-tight site-footer">
      <p className="prose-column">
        Разборы на сайте — {providers.length * contractNames.length} дословных ответов сервиса:{" "}
        {providers.length} описания в {contractNames.length} контрактах, снятые {dayAndMonth}{" "}
        {yearWithoutAbbreviation} года. Живой режим отправляет ваше описание в работающий сервис.
      </p>
      <div className="site-footer-links">
        <button className="link" onClick={() => go("/docs")}>
          Документация
        </button>
        <GithubLink
          href="https://github.com/GoatWhistle/genesis-hack"
          label="Исходники на GitHub"
        />
      </div>
    </div>
  </footer>
);
