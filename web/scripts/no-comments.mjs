import { readdir, readFile } from "node:fs/promises";
import { join, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";

const SRC = join(dirname(fileURLToPath(import.meta.url)), "..", "src");
const CHECKED = new Set([".ts", ".tsx", ".css"]);

const walk = async (dir) => {
  const entries = await readdir(dir, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map((entry) => {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) return walk(path);
      return CHECKED.has(extname(entry.name)) ? [path] : [];
    })
  );
  return nested.flat();
};

const stripStrings = (source) =>
  source
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/'(?:\\.|[^'\\])*'/g, "''")
    .replace(/`(?:\\.|[^`\\])*`/g, "``")
    .replace(/https?:\/\//g, "url")
    .replace(/\/(?![/*])(?:\\.|\[(?:\\.|[^\]\\])*\]|[^/\\\n])+\/[gimsuy]*/g, "re");

const findings = [];

for (const file of await walk(SRC)) {
  const lines = (await readFile(file, "utf8")).split("\n");
  let insideBlock = false;

  lines.forEach((line, index) => {
    const clean = stripStrings(line);

    if (insideBlock) {
      findings.push([file, index + 1, line.trim()]);
      if (clean.includes("*/")) insideBlock = false;
      return;
    }

    if (clean.includes("//") || clean.includes("/*")) {
      findings.push([file, index + 1, line.trim()]);
      if (clean.includes("/*") && !clean.includes("*/")) insideBlock = true;
    }
  });
}

if (findings.length > 0) {
  console.error(`комментарии во фронтенде запрещены, найдено ${findings.length}:`);
  for (const [file, line, text] of findings.slice(0, 40)) {
    console.error(`  ${file.replace(SRC, "src")}:${line}  ${text.slice(0, 90)}`);
  }
  process.exit(1);
}

console.log("комментариев нет");
