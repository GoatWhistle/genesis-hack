PROVIDER ?= novapay
SPEC     ?= examples/$(PROVIDER)/provider_api.yaml
CONTRACT ?= space_payments
OUT      ?= output
HOST     ?= 127.0.0.1
PORT     ?= 9292
STORAGE  ?= local
CLASSIFIER ?= rules
EXAMPLES ?= novapay kassabox nordbank swiftpay
KINDS    ?=

BUNDLE  := bundle exec
RSOCKET := $(BUNDLE) bin/rsocket

.DEFAULT_GOAL := help
.PHONY: help install check test lint lint-fix build examples doctor contracts \
        serve rackup request up down logs push clean bench specs

help: ## показать этот список
	@echo "Команды:"
	@grep -hE '^[a-z][a-zA-Z0-9_-]*:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN { FS = ":.*## " } { printf "  %-10s %s\n", $$1, $$2 }'
	@echo ""
	@echo "Переменные: PROVIDER=$(PROVIDER) SPEC=$(SPEC) CONTRACT=$(CONTRACT)"
	@echo "            OUT=$(OUT) HOST=$(HOST) PORT=$(PORT) STORAGE=$(STORAGE)"
	@echo "            CLASSIFIER=$(CLASSIFIER)"

install: ## поставить гемы
	bundle install

check: test lint ## тесты и линтер разом

test: ## прогнать тесты
	$(BUNDLE) rspec

lint: ## прогнать линтер
	$(BUNDLE) rubocop

lint-fix: ## поправить то, что линтер умеет править сам
	$(BUNDLE) rubocop --autocorrect

build: ## собрать интеграцию: make build PROVIDER=novapay [SPEC=... CONTRACT=... CLASSIFIER=...]
	$(RSOCKET) build --spec $(SPEC) --provider $(PROVIDER) \
		--contract $(CONTRACT) --out $(OUT) --classifier $(CLASSIFIER)

specs: ## скачать описания чужих провайдеров в bench/specs/ (см. bench/specs/SOURCES.md)
	bench/fetch_specs.sh

bench: ## замерить три способа раздачи ролей: make bench [KINDS="rules llm"]
	$(BUNDLE) ruby bench/classifiers.rb $(KINDS)

examples: ## собрать все примеры из examples/
	@for provider in $(EXAMPLES); do \
		$(RSOCKET) build --spec examples/$$provider/provider_api.yaml \
			--provider $$provider --contract $(CONTRACT) --out $(OUT) || exit 1; \
		echo ""; \
	done

doctor: ## показать правила, по которым разбираются описания
	$(RSOCKET) doctor --contract $(CONTRACT)

contracts: ## показать профили контрактов
	$(RSOCKET) contracts

serve: ## поднять HTTP-сервер: make serve [PORT=8080 STORAGE=s3]
	$(RSOCKET) serve --storage $(STORAGE) --host $(HOST) --port $(PORT)

rackup: ## то же самое через config.ru и любой сервер приложений
	RSOCKET_STORAGE=$(STORAGE) $(BUNDLE) rackup --host $(HOST) --port $(PORT)

request: ## отправить описание на уже поднятый сервер и разложить ответ по файлам
	@mkdir -p $(OUT)/$(PROVIDER)
	@curl -sS -X POST \
		"http://$(HOST):$(PORT)/build?provider=$(PROVIDER)&contract=$(CONTRACT)" \
		--data-binary @$(SPEC) \
	| ruby -rjson -e 'answer = JSON.parse($$stdin.read); \
		abort(answer["error"]) if answer["error"]; \
		answer["warnings"].each { |warning| puts "  ! #{warning}" }; \
		answer["files"].each { |name, body| \
			path = File.join("$(OUT)/$(PROVIDER)", name); \
			File.write(path, body); puts "  #{path}" }'

up: ## поднять стек в контейнерах: MinIO и сервер на localhost:9292
	docker compose up --build

down: ## остановить стек
	docker compose down

logs: ## смотреть логи сервера в контейнере
	docker compose logs -f rsocket

push: ## перенести локальные правила и шаблоны в S3
	$(RSOCKET) push

clean: ## удалить собранное из output/
	rm -rf $(OUT)/*
