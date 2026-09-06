import { Suspense, lazy } from "react";
import { AnimatePresence, motion } from "motion/react";
import { enterVariants, useSwapTransition } from "~/shared/lib/motion";
import { useRoute } from "./useRoute";
import { SiteHeader } from "./SiteHeader";

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
  const transition = useSwapTransition();
  const Page = LAZY_PAGES[path];

  return (
    <>
      <a className="skip" href="#main">
        К содержимому
      </a>
      <SiteHeader path={path} go={go} />
      <main id="main">
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={path}
            variants={enterVariants}
            initial="hidden"
            animate="shown"
            exit="gone"
            transition={transition}
            onAnimationStart={() => window.scrollTo({ top: 0 })}
          >
            <Suspense
              fallback={
                <div className="shell-wide band label" role="status">
                  Загружаем…
                </div>
              }
            >
              <Page go={go} />
            </Suspense>
          </motion.div>
        </AnimatePresence>
      </main>
    </>
  );
};
