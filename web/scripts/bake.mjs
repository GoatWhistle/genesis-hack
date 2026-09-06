// Запекание прогонов: гонит настоящий POST /build по всем описаниям из examples/
// и по всем контрактам, складывает ответы в src/data/runs/.
//
// Зачем: сайт обязан работать, даже если бэкенд лежит. Запечённые прогоны — это
// не выдуманные фикстуры, а дословный ответ сервиса, поэтому CI сверяет их с
// живым API и краснеет при расхождении.
import { readFile, writeFile, mkdir, readdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const RUNS = join(HERE, "..", "src", "data", "runs");
const API = process.env.RSOCKET_API ?? "http://127.0.0.1:9292";

const fail = (message) => {
  console.error(`bake: ${message}`);
  process.exit(1);
};

const fetchJson = async (url, init) => {
  const response = await fetch(url, init).catch((error) =>
    fail(`${API} недоступен (${error.message}). Поднимите: docker compose up -d`)
  );
  const body = await response.text();
  if (!response.ok) fail(`${url} → ${response.status}: ${body.slice(0, 300)}`);
  return JSON.parse(body);
};

const providers = async () => {
  const entries = await readdir(join(REPO, "examples"), { withFileTypes: true });
  return entries.filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
};

const build = async (provider, contract) => {
  const spec = await readFile(join(REPO, "examples", provider, "provider_api.yaml"), "utf8");
  const query = new URLSearchParams({ provider, contract });
  return fetchJson(`${API}/build?${query}`, {
    method: "POST",
    headers: { "Content-Type": "application/yaml" },
    body: spec
  });
};

const main = async () => {
  await mkdir(RUNS, { recursive: true });
  const { contracts } = await fetchJson(`${API}/contracts`);
  const names = contracts.map((contract) => contract.name);
  const list = await providers();

  await writeFile(join(RUNS, "contracts.json"), `${JSON.stringify(contracts, null, 2)}\n`);

  for (const provider of list) {
    for (const contract of names) {
      const outcome = await build(provider, contract);
      const file = join(RUNS, `${provider}.${contract}.json`);
      await writeFile(file, `${JSON.stringify(outcome, null, 2)}\n`);
      const roles = Object.keys(outcome.report?.roles ?? {}).length;
      console.log(`bake: ${provider} × ${contract} — ролей ${roles}, файлов ${Object.keys(outcome.files).length}`);
    }
  }

  // Правила тоже кладём в бандл: страница правил обязана открываться, когда
  // сервис недоступен, а показывать пустоту вместо base.yml нечестно.
  const { files } = await fetchJson(`${API}/rules`);
  const rules = {};
  for (const file of files) {
    const body = await fetchJson(`${API}/rules/${file.key}`);
    rules[file.key] = { kind: file.kind, content: body.content };
  }
  await writeFile(join(RUNS, "rules.json"), `${JSON.stringify(rules, null, 2)}
`);
  console.log(`bake: правил и шаблонов — ${Object.keys(rules).length}`);

  const index = { api: API, baked: new Date().toISOString(), providers: list, contracts: names };
  await writeFile(join(RUNS, "index.json"), `${JSON.stringify(index, null, 2)}\n`);
  console.log(`bake: готово — ${list.length * names.length} прогонов`);
};

await main();
