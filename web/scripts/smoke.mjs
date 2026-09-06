import { readFile, readdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DIST = join(ROOT, "dist");
const RUNS = join(ROOT, "src", "data", "runs");

const problems = [];
const check = (ok, message) => {
  if (!ok) problems.push(message);
};

const distFiles = await readdir(join(DIST, "assets")).catch(() => null);
if (!distFiles) {
  console.error("smoke: нет каталога dist/assets — сначала pnpm build");
  process.exit(1);
}

const html = await readFile(join(DIST, "index.html"), "utf8");
check(html.includes("<title>"), "в index.html нет заголовка страницы");
check(html.includes('lang="ru"'), "index.html не объявлен русским");
check(html.includes("favicon.svg"), "не подключён favicon");
check(/<script[^>]+type="module"/.test(html), "нет точки входа скрипта");

const entry = distFiles.filter((name) => /^index-.*\.js$/.test(name));
check(entry.length === 1, `ожидался один входной чанк, найдено ${entry.length}`);

if (entry[0]) {
  const bytes = (await readFile(join(DIST, "assets", entry[0]))).length;
  const limit = 400 * 1024;
  check(
    bytes <= limit,
    `входной чанк ${(bytes / 1024).toFixed(0)} КБ при пороге ${limit / 1024} КБ`
  );
  console.log(`smoke: входной чанк ${(bytes / 1024).toFixed(0)} КБ`);
}

const index = JSON.parse(await readFile(join(RUNS, "index.json"), "utf8"));
for (const provider of index.providers) {
  for (const contract of index.contracts) {
    const file = join(RUNS, `${provider}.${contract}.json`);
    const run = JSON.parse(await readFile(file, "utf8"));
    check(run.provider === provider, `${provider}.${contract}: чужой провайдер в прогоне`);
    check(Object.keys(run.files).length >= 3, `${provider}.${contract}: мало собранных файлов`);
    check(Boolean(run.report?.roles), `${provider}.${contract}: в отчёте нет ролей`);
    const bound = Object.values(run.report.roles).filter(
      (role) => role.status !== "заглушка"
    ).length;
    check(bound >= 2, `${provider}.${contract}: распознано ролей ${bound}, ожидали хотя бы две`);
  }
}

const rules = JSON.parse(await readFile(join(RUNS, "rules.json"), "utf8"));
check(Boolean(rules["base.yml"]?.content), "в запечённых правилах нет base.yml");

if (problems.length > 0) {
  console.error(`smoke: не сошлось ${problems.length}:`);
  for (const problem of problems) console.error(`  ${problem}`);
  process.exit(1);
}

console.log(`smoke: сборка и ${index.providers.length * index.contracts.length} прогонов в порядке`);
