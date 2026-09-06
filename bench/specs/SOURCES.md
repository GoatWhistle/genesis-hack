# Откуда эти файлы

Описания API чужих провайдеров, скачанные для замеров классификаторов. Сами файлы в
репозитории не лежат — они в `.gitignore`. Здесь только откуда что взято, на каких
условиях и что с этим делает наш код. Отбор и выводы — в
[bench/candidates.md](../candidates.md).

Скачать всё заново:

```
make specs                 # или bench/fetch_specs.sh
INSECURE=1 make specs      # вместе с Т-Банком, см. примечание внизу
```

Скачано 6 сентября 2026 года. Провайдеры свои описания меняют, так что размеры и число
операций — на ту дату. Адреса живут в `bench/fetch_specs.sh`: держать их ещё и здесь
значит однажды их разойти.

## Что скачано

| Файл | Размер | OpenAPI | Операций | Лучший на `create_request` | Счёт |
| --- | --- | --- | --- | --- | --- |
| `interledger.yaml` | 62 КБ | 3.1.0 | 10 | `create_incoming_payment` | 15 |
| `openbanking-uk-pis.json` | 569 КБ | 3.0.0 | 41 | `create_domestic_payment_consents` | 15 |
| `square.json` | 3.1 МБ | 3.0.0 | 334 | `create_payment_link` | 15 |
| `velo-payments.json` | 847 КБ | 3.0.2 | 100 | `submit_payout_v3` | 15 |
| `bunq.json` | 1.9 МБ | 3.0.0 | 421 | `create_payment_service_provider_credential` | 13 |
| `tbank-t-api.yaml` | 5.0 МБ | 3.0.1 | 475 | `create_salary_registry_payment` | 13 |
| `paypal-payouts-v1.json` | 74 КБ | 3.0.3 | 4 | `payouts.post` | 9 |
| `paystack.yaml` | 508 КБ | 3.0.1 | 163 | `charge_create` | 9 |
| `stripe.yaml` | 6.1 МБ | 3.0.0 | 594 | `post_charges` | 9 |
| `adyen-fund-v6.json` | 80 КБ | 3.1.0 | 8 | `post_payout_account_holder` | 7 |
| `adyen-payout-v68.yaml` | 91 КБ | 3.1.0 | 6 | `post_payout` | 7 |
| `adyen-transfer-v4.yaml` | 213 КБ | 3.1.0 | 12 | `post_transfers` | 7 |
| `yookassa.yaml` | 330 КБ | 3.0.2 | 34 | `post_payments` | 6 |
| `nowpayments.json` | 110 КБ | 3.0.3 | 16 | `get_the_minimum_payment_amount` | 5 |
| `mollie.yaml` | 1.9 МБ | — | — | не читается | — |
| `nium.yaml` | 2.2 МБ | — | — | не читается | — |

## Лицензии

Если файлы соберутся переезжать в репозиторий, это надо решить до, а не после.

| Источник                                              | Лицензия                          |
| ----------------------------------------------------- | --------------------------------- |
| Adyen (`adyen-payout`, `adyen-transfer`)              | MIT                               |
| PayPal (`paypal-payouts`)                             | Apache-2.0                        |
| Stripe (`stripe`)                                     | MIT                               |
| Т-Банк (`tbank-t-api`)                                | Apache 2.0, объявлена в самой спеке |
| APIs.guru (`velo`, `adyen-fund`, `openbanking-uk`, `bunq`, `nowpayments`) | CC0 на коллекцию |
| ЮKassa (`yookassa`)                                   | **не указана**                    |
| Mollie (`mollie`)                                     | **не указана**                    |
| Nium, Paystack, Square, Interledger                   | **не проверяли**, упёрлись в лимит GitHub API |

## Как читать таблицу выше

Столбец «счёт» — сколько набрал лучший кандидат на `create_request` у классификатора на
правилах при пороге 10. Роль обязательная: не набрала — сборка останавливается. Но
высокий счёт ещё не значит «угадал»:

- `velo-payments` — **единственный, где правила взяли верную операцию.**
- `square`, `bunq`, `openbanking-uk-pis`, `interledger` — счёт 13–15, и все четыре
  выбраны неверно: ссылка на оплату вместо выплаты, заведение учётки провайдера вместо
  платежа, согласие на платёж вместо платежа, входящий платёж вместо исходящего. Это
  хуже отказа: правила уверенно молчат об ошибке.
- `stripe`, `paystack` не добрали до порога, хотя нужная операция в описании есть
  (`post_payouts` у Stripe, `transfer_*` у Paystack). Выиграл в обоих случаях приём
  платежа: `post_charges` и `charge_create`.
- у `square` создания выплаты нет вовсе — только чтение (`list_payouts`, `get_payout`),
  так что верного ответа там и не существует.

## Что не читается

`mollie` и `nium` наш загрузчик не открывает:

```
не разобрать YAML: Tried to load unspecified class: Time
```

`YAML.safe_load` в `Adapter::Loader::Document` не разрешает `Time`, а в обоих описаниях
есть голая дата без кавычек. Это наше ограничение, а не их проблема; чинится
`permitted_classes`.

## Примечание про Т-Банк

`business.tinkoff.ru` отдаёт цепочку сертификатов, подписанную корневым сертификатом
Минцифры, которого нет в хранилище macOS. Файл скачан с `INSECURE=1`, то есть **без
проверки сертификата**, и по умолчанию `make specs` его пропускает. Для описания, которое
пойдёт в тесты, это плохо: подмену никто не заметит. Правильно — поставить корневой
сертификат Минцифры. Тем же упирается `developers.tochka.com`, поэтому Точки здесь нет.
