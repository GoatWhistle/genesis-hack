export const ROUTES = [
  { path: "/", title: "RSOCKET", nav: "Начало" },
  { path: "/lab", title: "Разбор документа", nav: "Разбор" },
  { path: "/rules", title: "Правила разбора", nav: "Правила" },
  { path: "/providers", title: "Провайдеры", nav: "Провайдеры" },
  { path: "/docs", title: "Документация", nav: "Документация" }
] as const;

export type RoutePath = (typeof ROUTES)[number]["path"];

export const isRoute = (value: string): value is RoutePath =>
  ROUTES.some((route) => route.path === value);
