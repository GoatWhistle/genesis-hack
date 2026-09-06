# Выкладка на genesis.goatwhistle.ru

Production состоит из отдельного Docker Compose-проекта `genesis` и общего edge-Caddy,
который уже обслуживает домены на VPS.

Путь запроса:

    genesis.goatwhistle.ru
      -> timeline-caddy-1
      -> genesis-web:80
         -> статика из /srv/genesis/current
         -> /api/* -> rsocket:9292

MinIO и Ruby-сервис доступны только внутри Docker-сети проекта. Контейнер `web`
подключён также к внешней сети `timeline_timeline`, где его видит общий Caddy.

## Раскладка на VPS

    /srv/genesis/
      repo/                 клон репозитория
      releases/<sha>/       собранная статика каждого выпуска
      current -> releases/<sha>
      previous.path         предыдущий выпуск для отката

## Однократная подготовка

На сервере должны быть Docker, Compose, Git и rsync. Репозиторий и каталоги:

    sudo mkdir -p /srv/genesis/releases
    sudo chown -R user1:user1 /srv/genesis
    git clone https://github.com/GoatWhistle/genesis-hack.git /srv/genesis/repo

В Caddy, подключённый к сети `timeline_timeline`, добавляется блок из
`web/infra/Caddyfile`:

    genesis.goatwhistle.ru {
      encode zstd gzip
      reverse_proxy genesis-web:80
    }

## GitHub Environment production

Secrets:

- `SSH_KEY` — отдельный приватный deploy-key;
- `SSH_HOST` — `213.171.25.178`;
- `SSH_USER` — `user1`.

Variable:

- `SITE_URL` — `https://genesis.goatwhistle.ru`.

## Автоматическая выкладка

Push в `main` или `codex/deploy-genesis`, затрагивающий приложение или инфраструктуру,
запускает `.github/workflows/deploy.yml`:

1. Устанавливает зависимости и проверяет frontend.
2. Собирает статику.
3. Загружает её в `/srv/genesis/releases/<sha>` и атомарно переключает `current`.
4. Переключает серверный клон на тот же commit.
5. Выполняет `docker compose -p genesis -f web/infra/compose.prod.yaml up -d --build --wait`.
6. Проверяет главную страницу и `/api/health`; при ошибке возвращает предыдущую статику.

Ручная диагностика:

    cd /srv/genesis/repo
    docker compose -p genesis -f web/infra/compose.prod.yaml ps
    docker compose -p genesis -f web/infra/compose.prod.yaml logs --tail=200

Публичная проверка:

    curl -I https://genesis.goatwhistle.ru/
    curl https://genesis.goatwhistle.ru/api/health
