import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "~/layout/App";
import "~/shared/design/tokens.css";
import "~/shared/design/primitives.css";

const root = document.getElementById("root");
if (!root) throw new Error("нет узла #root");

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>
);
