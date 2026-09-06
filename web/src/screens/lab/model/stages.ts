export interface Stage {
  id: string;
  title: string;
  role: string;
  files: string[];
  what: string;
  why?: string;
  steps?: number[];
}

export const STAGES: Stage[] = [
  {
    id: "source",
    title: "Источник описания",
    role: "порт SpecSource",
    files: ["adapter/loader/file/spec_loader.rb", "adapter/loader/text/spec_reader.rb"],
    what: "Описание приходит либо файлом с диска, либо телом HTTP-запроса.",
    why: "Сценарий сборки не знает, откуда взялось описание. Поэтому команда и сервер — один и тот же код, а в тестах источник подменяется без файловой системы."
  },
  {
    id: "parse",
    title: "Разбор",
    role: "Parsing",
    files: [
      "service/adapter_builder/parsing/spec_parser.rb",
      "service/adapter_builder/parsing/schema_resolver.rb",
      "service/adapter_builder/parsing/schema_probe.rb"
    ],
    what: "OpenAPI раскладывается в список операций: метод, путь, operationId, теги, схемы запроса и ответов. Ссылки $ref разрешаются.",
    steps: [1]
  },
  {
    id: "classify",
    title: "Раздача ролей",
    role: "Classification",
    files: ["service/adapter_builder/classification/classifier.rb"],
    what: "Каждой роли контракта достаётся лучшая из свободных операций: правила архетипа дают счёт, veto снимает кандидата, порог отсекает слабых.",
    why: "Роли раздаются по очереди, и занятая операция выбывает. Иначе создание выплаты и запрос статуса дрались бы за один эндпоинт. Ничьи разрешаются порядком объявления в описании — чтобы результат не зависел от порядка ключей в хеше.",
    steps: [2]
  },
  {
    id: "analyze",
    title: "Разбор смысла",
    role: "Analysis",
    files: [
      "analysis/status_mapper.rb",
      "analysis/error_mapper.rb",
      "analysis/constraint_miner.rb",
      "analysis/payload_builder.rb",
      "analysis/callback_analyzer.rb",
      "analysis/credentials_planner.rb",
      "analysis/blueprint_factory.rb"
    ],
    what: "Статусы сводятся к группам, ошибки — к смыслу, из схемы вынимаются ограничения, поля запроса сопоставляются с данными операции, разбирается подпись уведомления и способ авторизации.",
    why: "Всё, что здесь решено, попадает в отчёт с объяснением: у ограничения указан источник, у роли — сработавшие правила. Решение без объяснения проверить нельзя.",
    steps: [3, 4]
  },
  {
    id: "render",
    title: "Печать",
    role: "порт Renderer",
    files: ["service/adapter_builder/rendering/renderer.rb", "rendering/report.rb"],
    what: "Шаблоны профиля контракта печатают сервис, инструкцию и фикстуры. Рядом кладётся отчёт mapping.yml.",
    why: "Шаблоны лежат в хранилище правил, а не в коде. Поэтому новый контракт — это набор файлов, а не правка генератора.",
    steps: [5]
  },
  {
    id: "upload",
    title: "Куда сложить",
    role: "порт Upload::Store",
    files: ["adapter/upload/file.rb", "adapter/upload/s3.rb"],
    what: "Результат уходит в каталог output/ или в бакет — выбирается при запуске.",
    why: "Командная строка работает с диском, сервер — с бакетом, но сборка одна и та же."
  }
];

export const stageOfStep = (step: number) =>
  STAGES.find((stage) => stage.steps?.includes(step));
