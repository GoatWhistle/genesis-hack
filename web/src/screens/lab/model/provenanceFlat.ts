import type { Report } from "~/shared/api/types";
import type { Claim, ProvenanceSource } from "./provenanceLines";
import { isRubyLine, methodSpan } from "./provenanceLines";

export const flatClaims = (report: Report, lines: string[]): Claim[] => {
  const claims: Claim[] = [];
  const add = (source: ProvenanceSource, match: (line: string) => boolean, methods: string[] = []) => {
    const span = new Set(
      lines.flatMap((line, index) => (isRubyLine(line) && match(line) ? [index] : []))
    );
    for (const method of methods) for (const index of methodSpan(lines, method)) span.add(index);
    if (span.size > 0) claims.push({ source, lines: [...span].sort((a, b) => a - b) });
  };

  if (report.amount.multiplier !== 1) {
    add(
      {
        id: "amount",
        kind: "amount",
        title: `Множитель ×${report.amount.multiplier}`,
        summary: `Сумма умножается на ${report.amount.multiplier}: ${report.amount.note}.`,
        details: ["множитель выведен из единиц измерения поля суммы в описании"],
        side: "provider"
      },
      (line) => new RegExp(`\\*\\s*${report.amount.multiplier}\\b`).test(line)
    );
  }

  const header = report.callback.signature_header;
  if (header) {
    add(
      {
        id: "callback",
        kind: "callback",
        title: header,
        summary: `Подпись приходит в этом заголовке, алгоритм ${report.callback.algorithm ?? "не указан"}.`,
        details: [
          report.callback.operation_id_field
            ? `идентификатор операции берётся из поля ${report.callback.operation_id_field}`
            : "поле идентификатора операции не найдено"
        ],
        side: "provider"
      },
      (line) =>
        line.includes(`"${header}"`) ||
        (report.callback.algorithm ? line.includes(`"${report.callback.algorithm}"`) : false) ||
        (report.callback.operation_id_field
          ? line.includes(`"${report.callback.operation_id_field}"`)
          : false),
      ["valid_signature", "callback_signature", "callback_body"]
    );
  }

  if (report.auth.primary) {
    add(
      {
        id: "auth",
        kind: "auth",
        title: report.auth.primary,
        summary: `Схема выбрана из securitySchemes описания.`,
        details: [
          report.auth.alternatives.length > 0
            ? `в описании также есть: ${report.auth.alternatives.join(", ")}`
            : "других схем в описании нет",
          ...report.auth.notes
        ],
        side: "provider"
      },
      (line) => line.includes(`Авторизация: ${report.auth.primary}`),
      ["authorize"]
    );
  }

  if (report.base_url) {
    add(
      {
        id: "base_url",
        kind: "base_url",
        title: report.base_url,
        summary: "Взят из блока servers описания.",
        details: ["значение подставлено как запасное: приоритет у переменной окружения"],
        side: "provider"
      },
      (line) => line.includes(report.base_url ?? "")
    );
  }

  return claims;
};

