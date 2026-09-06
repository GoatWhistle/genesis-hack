import { Suspense, lazy } from "react";
import { useRoute } from "./useRoute";
import { SiteHeader } from "./SiteHeader";
import { SiteFooter } from "./SiteFooter";

const Home = lazy(() => import("~/screens/home/ui/HomePage"));
const Lab = lazy(() => import("~/screens/lab/ui/LabPage"));
const Rules = lazy(() => import("~/screens/rules/ui/RulesPage"));
const Providers = lazy(() => import("~/screens/providers/ui/ProvidersPage"));
const Docs = lazy(() => import("~/screens/docs/ui/DocsPage"));

const LAZY_PAGES = {
  "/": Home,
  "/lab": Lab,
  "/rules": Rules,
  "/providers": Providers,
  "/docs": Docs
} as const;

export const App = () => {
  const { path, go } = useRoute();
  const Page = LAZY_PAGES[path];

  return (
    <>
      <a className="skip" href="#main">
        К содержимому
      </a>
      <SiteHeader path={path} go={go} />
      <main id="main">
        <Suspense
          fallback={
            <div className="shell-wide band label" role="status">
              Загружаем…
            </div>
          }
        >
          <Page go={go} />
        </Suspense>
      </main>
      <SiteFooter go={go} />
    </>
  );
};
