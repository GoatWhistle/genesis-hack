# Проверка feat/classifier-recognition

Дата: 6 сентября 2026. Исходный HEAD: `91a6df171c6f3968f1474c0e3c0fcf02e1a50fc4`
(в task.md аудит указан для `7ddb793`). Ruby 3.3.12, Bundler 4.0.20.

Исправлены три дефекта, добавлено 28 регрессионных примеров в `spec/`.
Полный RSpec: **303/303 до изменений, 331/331 после**. Эталонные данные и
правила оценки ролей не менялись. Изменения локальные; слияние и деплой не выполнялись.

## Изменения

- Swagger 2.0: ссылки общих parameters/responses раскрываются в исходном документе
  до переноса body и response.schema в content. Параметры пути наследуются операцией;
  параметры операции перекрывают их по in/name. Сохранены inline-схемы и definitions.
- Статус/отмена: сравнивается полный ресурсный путь с положением родительских
  идентификаторов. Удаляются только конечное действие и идентификатор ресурса.
  Совпадающие operationId или поля ответа не перекрывают конфликт ресурсов.
  Сохранены REST, RPC create/get, cancel, abort, revoke/revocation.
- Callback: парсер сохраняет ссылку на родительскую операцию вложенного callback.
  Она приоритетнее имени webhook. Для самостоятельных событий проверяются слова
  ресурса в пути/имени/тегах и специфичные поля payload. Признаки другого платёжного
  потока исключают кандидата. При равных доказательствах роль остаётся неназначенной
  с объяснением. Без распознанного создания callback не назначается.

## Проверки

Окружение команд:

```sh
export PATH="/opt/homebrew/opt/ruby@3.3/bin:$PATH"
export LANG=en_US.UTF-8
export BUNDLE_PATH=vendor/bundle
export BUNDLE_WITHOUT=classifiers
bundle install
```

До изменений приложения:

```sh
bundle exec rspec --exclude-pattern '**/{swagger2_references,resource_regressions,callback_regressions}_spec.rb'
```

Названия исключений соответствуют первым версиям новых тестов, впоследствии
переименованным. Результат: 303 примера, 0 ошибок, seed 44506. В sandbox первый
запуск дал 12 ошибок из-за запрета bind(127.0.0.1); повтор с разрешёнными локальными
сокетами прошёл. Это ограничение окружения, а не дефект приложения.

Первый запуск 20 новых сценариев на исходном приложении дал 15 ошибок:
5 Swagger, 5 связи ресурсов, 5 выбора callback. После исправлений добавлены ещё
8 проверок границ и наследования; всего 28 новых примеров.

Итоговые команды:

```sh
bundle exec rspec
bundle exec rubocop --cache false app/boot.rb app/models/api_operation.rb \
  app/service/adapter_builder/classification/{classifier,coherence,callback_coherence}.rb \
  app/service/adapter_builder/parsing/{operation_parser,swagger2_normalizer}.rb \
  spec/service/adapter_builder/classification/{coherence_regressions,classifier_callbacks}_spec.rb \
  spec/service/adapter_builder/parsing/spec_parser_swagger2_references_spec.rb
git diff --check
```

Результат: 331 пример, 0 ошибок, seed 33976; RuboCop — 10 файлов без замечаний;
проверка diff — без ошибок. Полный RSpec выполнялся с разрешёнными localhost-сокетами.

## Назначения до/после

Доступны только четыре описания из `examples/`. Снимки получены отдельно через
SpecLoader → SpecParser → Classifier с контрактом space_payments и сравнены
по каждой роли и каждому провайдеру. Все 16 назначений совпали:

| Провайдер | create_request | fetch_status | process_callback | cancel_request |
| --- | --- | --- | --- | --- |
| kassabox | make_transfer | transfer_info | отказ | abort_transfer |
| nordbank | create_payment_order | get_payment_order | отказ | revoke_payment_order |
| novapay | create_payout | get_payout_status | payout_webhook | cancel_payout |
| swiftpay | submit_transfer | fetch_transfer | отказ | revoke_transfer |

Относительно существующих ожиданий этих примеров: новых ложных назначений,
пропусков или выборов неправильной операции нет. На промежуточной версии
проверки ресурса пропали abort_transfer и revoke_payment_order. Причина — отсутствие
abort/revocation в списке конечных действий; исправлено, оба назначения восстановлены.

Разбор изменений на синтетических контрпримерах:

| Категория | До | После |
| --- | --- | --- |
| Swagger shared body/response | nil вместо схемы | схема definitions раскрыта |
| Swagger path parameters | отсутствующая schema | тип сохранён; наследование и override проверены |
| Родитель/дочерний ресурс, batch/item, ACH/wire | ложная связь при совпадающих именах/схемах | отказ от связи |
| webhook_payment_links и webhook_payouts | выбрано чужое событие | выбран webhook_payouts |
| Приём платежа/карточная авторизация | ложное назначение callback | отказ |
| Два одинаково обоснованных payout-события | первое по порядку | безопасный отказ с объяснением |
| Одноимённые вложенные callbacks разных родителей | родитель утрачен, выбор по порядку | выбран callback создания выплаты |

Отказ при двух payout-событиях может быть пропуском полезного callback. Это
сознательное ограничение: без дополнительного доказательства выбрать единственную
операцию нельзя. Синтетический пример с именами TrueLayer не заменяет проверку
на самом описании TrueLayer.

## Ограничения и рекомендация

`bench/`, оба корпуса, truth.yml/truth-new.yml и measure.rb отсутствуют в свежем
клоне. Команда `bundle exec ruby bench/measure.rb bench/truth.yml bench/truth-new.yml`
недоступна. Сравнение 71 описания и подробная проверка каждого провайдера этих
корпусов **не выполнены**; исходные числа из task.md не выдаются за наш замер.

Известное ложное назначение выплаты у GOV.UK Pay не исправлялось и не перепроверялось:
описания нет. Это остаётся известным дефектом, а не «продуктовой неоднозначностью».
Группа holdout уже использовалась при настройке и не является независимой проверкой.

Структурная связь намеренно консервативна: нестандартные RPC-адреса и разные
наименования одного потока могут остаться без роли. Для callback неполные имена,
неизвестные синонимы, неоднозначные события и недостаточная схема дают отказ.
LLM, embeddings, внешних вызовов классификатора и исключений по провайдерам нет.

Исправление Swagger готово к отдельному review/слиянию по доступным проверкам.
**Слияние всей ветки пока не рекомендовано**: остаётся известный GOV.UK Pay и
нет повторного замера обоих корпусов. Перед общим слиянием нужен этот замер с
разбором изменившихся назначений. Успешные unit-тесты и тесты с локальным сервером
не доказывают работоспособность реальной интеграции с платёжным провайдером.

Локальные логи: tmp/rspec-before-unrestricted.log, tmp/regressions-before.log,
tmp/rspec-after.log, tmp/rubocop-final.log, tmp/before.json, tmp/after.json.
Каталог tmp игнорируется Git.
