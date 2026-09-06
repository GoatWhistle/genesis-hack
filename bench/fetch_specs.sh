#!/usr/bin/env bash
# Качает описания API провайдеров в bench/specs/. Сами файлы в репозитории не
# лежат — часть без лицензии, часть по несколько мегабайт; откуда что взято и на
# каких условиях, записано в bench/specs/SOURCES.md.
#
#   bench/fetch_specs.sh            # всё, что качается с проверкой сертификата
#   INSECURE=1 bench/fetch_specs.sh # ещё и Т-Банк, см. примечание ниже
set -u

cd "$(dirname "$0")/.."
DIR=bench/specs
mkdir -p "$DIR"

fetch() {
  local file=$1 url=$2
  shift 2
  printf '%-24s ' "$file"
  if curl -sSL -m 300 "$@" -o "$DIR/$file" "$url"; then
    printf '%s байт\n' "$(wc -c < "$DIR/$file" | tr -d ' ')"
  else
    printf 'НЕ СКАЧАЛОСЬ\n'
    rm -f "$DIR/$file"
  fi
}

fetch adyen-payout-v68.yaml   https://raw.githubusercontent.com/Adyen/adyen-openapi/main/yaml/PayoutService-v68.yaml
fetch adyen-transfer-v4.yaml  https://raw.githubusercontent.com/Adyen/adyen-openapi/main/yaml/TransferService-v4.yaml
fetch paypal-payouts-v1.json  https://raw.githubusercontent.com/paypal/paypal-rest-api-specifications/main/openapi/payments_payouts_batch_v1.json
fetch yookassa.yaml           https://yookassa.ru/developers/api/yookassa-openapi-specification.yaml
fetch velo-payments.json      https://api.apis.guru/v2/specs/velopayments.com/2.34.63/openapi.json
fetch mollie.yaml             https://raw.githubusercontent.com/mollie/openapi/master/specs.yaml
fetch nium.yaml               https://raw.githubusercontent.com/nium-global/nium-openapi/main/nium.yaml
fetch stripe.yaml             https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.yaml
fetch paystack.yaml           https://raw.githubusercontent.com/PaystackOSS/openapi/main/dist/paystack.yaml
fetch square.json             https://raw.githubusercontent.com/square/connect-api-specification/master/api.json
fetch adyen-fund-v6.json      https://api.apis.guru/v2/specs/adyen.com/FundService/6/openapi.json
fetch openbanking-uk-pis.json https://api.apis.guru/v2/specs/openbanking.org.uk/payment-initiation-openapi/3.1.7/openapi.json
fetch bunq.json               https://api.apis.guru/v2/specs/bunq.com/1.0/openapi.json
fetch nowpayments.json        https://api.apis.guru/v2/specs/nowpayments.io/1.0.0/openapi.json
fetch interledger.yaml        https://raw.githubusercontent.com/interledger/open-payments-specifications/main/openapi/resource-server.yaml

# У business.tinkoff.ru цепочка сертификатов подписана корнем Минцифры, которого нет
# в хранилище macOS. Правильное решение — поставить этот корень; INSECURE=1 просто
# отключает проверку и потому по умолчанию выключен.
if [ "${INSECURE:-0}" = "1" ]; then
  fetch tbank-t-api.yaml      https://business.tinkoff.ru/openapi/docs/openapi.yaml -k
else
  printf '%-24s пропущен: нужен корневой сертификат Минцифры либо INSECURE=1\n' tbank-t-api.yaml
fi
