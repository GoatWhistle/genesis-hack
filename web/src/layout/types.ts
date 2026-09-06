import type { RoutePath } from "./routes";

export interface PageProps {
  go: (path: RoutePath, search?: string) => void;
}
