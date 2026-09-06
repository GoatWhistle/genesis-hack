import { GithubLink } from "~/shared/design/GithubLink";
import type { PageProps } from "./types";

export const SiteFooter = ({ go }: PageProps) => (
  <footer className="rule-line">
    <div className="shell-wide band-tight site-footer">
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
