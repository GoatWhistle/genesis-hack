import type { RoutePath } from "./routes";

export interface PageProps {
  go: (path: RoutePath) => void;
}
