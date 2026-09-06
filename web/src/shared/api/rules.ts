import raw from "~/data/runs/rules.json";

export interface RuleFile {
  kind: "rules" | "template";
  content: string;
}

const files = raw as Record<string, RuleFile>;

export const ruleKeys = Object.keys(files).sort();

export const ruleFile = (key: string): RuleFile | undefined => files[key];

export const ruleGroups = (): { title: string; keys: string[] }[] => {
  const base = ruleKeys.filter((key) => !key.startsWith("contracts/"));
  const byContract = new Map<string, string[]>();

  for (const key of ruleKeys) {
    const match = /^contracts\/([^/]+)\//.exec(key);
    if (!match?.[1]) continue;
    const list = byContract.get(match[1]) ?? [];
    list.push(key);
    byContract.set(match[1], list);
  }

  return [
    { title: "Общие правила разбора", keys: base },
    ...[...byContract.entries()].map(([name, keys]) => ({ title: `Контракт ${name}`, keys }))
  ];
};

export const ruleLanguage = (key: string): string => {
  if (key.endsWith(".erb")) return "erb";
  if (key.endsWith(".yml") || key.endsWith(".yaml")) return "yaml";
  if (key.endsWith(".json")) return "json";
  return "text";
};
