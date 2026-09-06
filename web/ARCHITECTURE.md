# Архитектура фронтенда

## Раскладка

```
src/
├── main.tsx
├── data/runs/                 запечённые прогоны, профили контрактов, правила
├── shared/                    общее для двух и более экранов
│   ├── api/                   клиент, запечённые прогоны, правила, типы
│   ├── model/                 чистая логика без React
│   ├── ui/                    переиспользуемые компоненты
│   ├── lib/                   хуки общего назначения
│   └── design/                токены, примитивы, знак проекта, тема кода
├── layout/                    App, SiteHeader, SiteFooter, routes, useRoute, types
└── screens/
    ├── home/{ui,model}/
    ├── lab/{ui,model}/
    ├── rules/{ui,model}/
    ├── providers/{ui,model}/
    └── docs/{ui,model}/
```

Пять экранов, по одному на маршрут. Все подключены в `layout/App.tsx` через
`lazy`, поэтому каждый уезжает в свой чанк.

## Правила

1. **Экран — каталог, а не файл.** Внутри `ui/` (React) и `model/` (чистые
   функции и данные). Проверяемое отделено от рисуемого.
2. **`shared/` — только то, что нужно двум и более экранам.** Утащить туда
   «на всякий случай» так же плохо, как продублировать.
3. **Экран не импортирует из чужого экрана.** Понадобилось — значит, это
   `shared/`. Закреплено линтером (`no-restricted-imports` на каждый экран).
4. **`shared/` не зависит ни от экранов, ни от каркаса.** Тоже закреплено
   линтером: импорт `~/screens/*` и `~/layout/*` внутри `shared/` — ошибка.
5. **CSS рядом с тем, что красит.** Общее — в `shared/design/`, частное — в
   каталоге своего экрана. `.side-grid` живёт в `shared/ui/sidenav.css`,
   потому что красит раскладку вокруг `SideNav`.
6. **Файл до 250 строк.** Больше — значит, делает две вещи (`max-lines`).
7. **Комментариев в `src/` нет.** Ни `//`, ни `/* */`, ни `{/* */}`. Проверяет
   `scripts/no-comments.mjs` в составе `pnpm lint`. В конфигах и `scripts/`
   комментарии разрешены и нужны.

## Псевдонимы путей

| Псевдоним | Куда |
|---|---|
| `~/shared/*` | `src/shared/*` |
| `~/layout/*` | `src/layout/*` |
| `~/screens/*` | `src/screens/*` |
| `~/*` | `src/*` — остался для `~/data/runs/*` |

Заданы дважды: в `tsconfig.json` (для типов) и в `vite.config.ts` (для сборки).
Меняя один — правьте оба.

## Как устроено сейчас

Переезд сделан, разрозненные реализации сведены.

Сведено в `shared/`:

- подсветка кода — `shared/lib/useHighlight` со своей темой
  `shared/design/codeTheme`; ей пользуются `lab/StepCode`, `lab/TracedCode`,
  `rules/Templates`;
- загрузка прогонов — `shared/api/runs` (ленивый `import.meta.glob` с кешем)
  и хуки `shared/api/useRun`, `shared/api/useRuns`; отдельных загрузчиков у
  `home` и `providers` больше нет;
- вкладки файлов — `shared/ui/FileTabs`, внутри — `shared/ui/Markdown`;
- запись терминала — `shared/ui/Terminal`, тип `Take` экспортируется оттуда же;
- боковое меню разделов — `shared/ui/SideNav`, общее для `/rules` и `/docs`;
- скачивание архива — `shared/ui/DownloadRun` поверх `shared/model/zip`,
  общее для `/lab` и `/providers`;
- разбор `base.yml` и сопоставление кандидатов — `shared/model/base` и
  `shared/model/match`, общие для `home/VetoBench` и всего экрана `rules`;
- история просмотров — `shared/lib/history`.

Осталось раздельно и намеренно:

- вкладки кода внутри `lab/StepCode` — это не `FileTabs`: они показывают код с
  разметкой происхождения строк (`TracedCode`), а не просто подсвеченный файл;
- `useProvenance`, `provenance*.ts` — только у `lab`, второго потребителя нет;
- хореография сцены `home/useChoreography` — только у главной;
- модель сравнения `providers/model/compare` — только у `/providers`;
- песочница правил `rules/model/sandboxModel` — только у `/rules`.
