# Фундамент сайта — читать до начала работы

Каркас готов: сборка, типы, линтер и данные на месте. Ниже то, что уже сделано
за вас, и правила, которые нельзя нарушать.

## Команды

    pnpm dev         разработка на 5173, /api проксируется на 127.0.0.1:9292
    pnpm typecheck   tsc --noEmit
    pnpm lint        запрет комментариев + eslint
    pnpm build       typecheck + сборка в dist/
    pnpm smoke       проверка собранного dist/ и запечённых прогонов
    pnpm bake        перезапекание прогонов с живого сервиса
    pnpm preview     просмотр собранного dist/

Полная проверка перед сдачей — четыре команды подряд:

    pnpm typecheck && pnpm lint && pnpm build && pnpm smoke

`pnpm smoke` требует уже собранного `dist/`, поэтому идёт после `pnpm build`.

Бэкенд поднимается `docker compose up -d` в корне репозитория, ручки на
`http://127.0.0.1:9292`. Проверить: `curl http://127.0.0.1:9292/health`.
Сайт работает и без него: все разборы запечены в сборку, сервис нужен только
для живого режима на `/lab` и для `pnpm bake`.

## Правила, обязательные для всех

- **Русский язык** во всём: интерфейс, имена в текстах.
- **250 строк на файл**, это проверяет `max-lines` в eslint. Больше — значит
  файл делает две вещи, разделите.
- **Одна тема** — светлая. Тёмной нет и не будет: сайт смотрят с проектора.
- **Никаких тестов** — не пишите ни vitest, ни playwright.
- **CSS переиспользуется.** Общие классы — в `src/shared/design/primitives.css`.
  Новый повторяющийся элемент добавляйте туда, а не копируйте разметку.
  Не тащите utility-классы Tailwind россыпью там, где нужен именованный класс.
- **Не трогайте ничего вне `web/`.** `app/`, `bin/`, `spec/`, `docs/` — чужой код.
- **Комментариев во фронтенде нет вообще.** Ни `//`, ни `/* */`, ни `{/* */}`,
  ни в `.tsx`, ни в `.ts`, ни в `.css`. Если код требует пояснения — переименуйте
  переменную или вынесите в функцию с говорящим именем. Это проверяет
  `scripts/no-comments.mjs`, он обходит весь `src/` и роняет `pnpm lint`.
  Запрет распространяется только на `src/`: в конфигах (`vite.config.ts`,
  `scripts/`, `infra/`) комментарии уместны и нужны.

## Данные

Всё уже запечено: `src/data/runs/` — 8 дословных ответов `POST /build`
(4 провайдера × 2 контракта) плюс `contracts.json`, `rules.json` и `index.json`.
Прогоны подгружаются лениво через `import.meta.glob`, в общий чанк не попадают.

```ts
import { useBakedRun } from "~/shared/api/useRun";
const { run, loading, error } = useBakedRun("novapay", "space_payments");
```

`run.report` содержит: `roles` (у связанной роли — `operation`, `endpoint`,
`score`, `threshold`, `matched_rules` с настоящими регулярками; у несвязанной —
`why`), `statuses`, `events`, `amount`, `conditions` (с `source`), `callback`,
`auth`, `warnings`. `run.files` — имя файла → его содержимое строкой
(`<provider>_service.rb`, `INTEGRATION.md`, `fixtures.json`, `mapping.yml`).

Помощники в `~/shared/api/runs`: `providers`, `contractNames`, `profiles`,
`bakedAt`, `roleOrder(contract)`, `roleTitle(contract, role)`,
`roleMeta(contract, role)`, `defaultProvider`, `defaultContract`, `hasRun`.

Несколько прогонов сразу — `useRunsByProvider(contract)` и `useAllRuns(contract)`
из `~/shared/api/useRuns`.

Правила и шаблоны запечены отдельно: `~/shared/api/rules` — `ruleKeys`,
`ruleFile(key)`, `ruleGroups()`.

Живой режим: `useLiveBuild()` из `~/shared/api/useRun`, клиент —
`~/shared/api/client` (`build`, `health`, `fetchContracts`, `readRule`,
`listRules`, класс `ApiError`).

Типы: `~/shared/api/types` (`BuildOutcome`, `Report`, `Role`, `isBound`,
`ContractProfile` и прочее).

## Дизайн

Токены — `src/shared/design/tokens.css`. Классы — `src/shared/design/primitives.css`.

**Цвет кодирует сторону данных, это главное правило системы:**

- `--color-provider` (киноварь) — всё, что пришло от провайдера: операции,
  поля, его статусы, YAML. Классы `.side-provider`, `.chip-provider`.
- `--color-contract` (ультрамарин) — всё, что уходит в контракт заказчика:
  роли, методы, статусы заказчика, сгенерированный код. `.side-contract`,
  `.chip-contract`.
- `--color-ink` — правило, которое их связало: регулярки, счёт, порог.
- Третьего яркого цвета нет. Veto и предупреждения — знаком и перечёркиванием
  (`.notice`), не заливкой.

**Ширины.** Одной рамки нет, их три — иначе на широком мониторе страница
читается как контейнер по центру:

- `.shell` — 78rem, для сплошного текста;
- `.shell-wide` — 108rem, для данных: таблиц, сцен, кода. Основная ширина
  страниц;
- `.shell-full` — без ограничения, только внутренние отступы.

Проза внутри широкой полосы держится узкой: `.read-column` (72ch, работает
прямым потомком `.shell-wide` или `.shell-full`) и `.prose-column` (68ch,
работает где угодно).

Готовые классы `primitives.css`: `.shell`, `.shell-wide`, `.shell-full`,
`.read-column`, `.prose-column`, `.band` / `.band-tight` (вертикальный ритм),
`.rule-line`, `.panel` / `.panel-quiet`, `.side-provider` / `.side-contract`,
`.chip` / `.chip-provider` / `.chip-contract` / `.chip-quiet`, `.btn`,
`.btn-primary`, `.btn-ghost`, `.switch` / `.switch-item`, `.mono`, `.label`,
`.notice` / `.notice-mark`, `.scroll-x`, `.link`, `.icon-link`, `.md`, `.skip`.
Каркас страницы — `.site-header*`, `.site-nav*`, `.site-mark`, `.site-wordmark`,
`.site-footer*`, знак — `.mark*`.

Двухколоночная раскладка «боковое меню + содержимое» — `.side-grid` вместе с
компонентом `SideNav` из `~/shared/ui/SideNav`; класс живёт в
`src/shared/ui/sidenav.css`, рядом с тем, что красит.

Шрифты подключены: Golos Text (текст), Martian Mono (код) — оба с кириллицей.

Подсветка кода — своя тема shiki, `~/shared/design/codeTheme`, через
`useHighlight` из `~/shared/lib/useHighlight`.

**Запрещено:** цветные полосы слева у карточек, градиентный текст, стекло,
«большая цифра + подпись» как шаблон метрики, сетки одинаковых карточек,
мелкий капс-кикер над каждым разделом, нумерация `01/02/03` там, где нет
настоящей последовательности, эмодзи вместо иконок, тени-пузыри.

**Движение:** только ease-out (`--ease-out-quart`, `--ease-out-expo`), без
bounce. Содержимое видно сразу — анимация показывает, как оно появилось, но
никогда не решает, видно ли его. `prefers-reduced-motion` уже обработан
глобально.

## Маршруты

Свой роутер (`~/layout/useRoute`), библиотеки нет. Пять страниц, перечислены в
`~/layout/routes`:

| Путь | Раздел |
|---|---|
| `/` | Начало |
| `/lab` | Разбор |
| `/rules` | Правила |
| `/providers` | Провайдеры |
| `/docs` | Документация |

Экраны лежат в `src/screens/<имя>/ui/<Имя>Page.tsx`, подключены в
`src/layout/App.tsx` через `lazy`. Каждый принимает `PageProps` (`{ go }`) из
`~/layout/types`. Неизвестный адрес выпрямляется в `/`.

Состояние в адресе: `useSearchParam(name, fallback)` из `~/layout/useRoute` —
им делается ссылка на конкретный разбор.

## Раскладка каталогов

Подробно — в [ARCHITECTURE.md](ARCHITECTURE.md). Коротко: `src/shared/`
(общее для двух и более экранов), `src/layout/` (каркас и роутер),
`src/screens/<экран>/{ui,model}/`. Псевдонимы — `~/shared/*`, `~/layout/*`,
`~/screens/*`. Экран не импортирует из чужого экрана, `shared/` не зависит ни
от экранов, ни от каркаса — оба правила закреплены линтером.
