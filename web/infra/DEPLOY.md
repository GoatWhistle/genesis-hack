# Выкладка сайта на VPS

Сайт — витрина поверх решения кейса. На сервере крутится их `compose.yaml`
как есть (minio, rules, rsocket), а сверху добавляется Caddy: он отдаёт статику
и проксирует `/api/*` в сервис. Один домен, один origin, CORS не нужен.

## Раскладка на сервере

    /srv/rsocket/
      repo/                 клон репозитория (нужен для docker compose)
      releases/<sha>/       выпуски сайта, по одному каталогу на коммит
      current -> releases/<sha>   симлинк на текущий выпуск
      previous.path         путь предыдущего выпуска, по нему идёт откат

Caddy монтирует `/srv/rsocket` целиком и читает `current/`. Именно симлинк, а
не подмена каталога: bind-том в Linux привязан к inode, и `mv` каталога со
статикой оставил бы контейнер с удалённым старым — выкладка «успешна», сайт
не меняется. Переключение симлинка контейнер видит сразу.

## Подготовка сервера — один раз

    sudo mkdir -p /srv/rsocket/releases
    sudo chown -R $USER:$USER /srv/rsocket
    git clone https://github.com/GoatWhistle/genesis-hack /srv/rsocket/repo

Нужны docker с плагином compose и rsync. Пользователь, под которым ходит
выкладка, должен уметь запускать docker без sudo (`usermod -aG docker <user>`).

Домен: в `web/infra/Caddyfile` первой строкой блока стоит `rsocket.example.com` —
замените на свой. Это единственное место в файле, зависящее от площадки.
Запись A должна уже указывать на VPS, иначе Let's Encrypt не выдаст сертификат.

Если на сервере **уже есть свой Caddy**, отдельный контейнер не нужен: возьмите
блок из `Caddyfile` в существующий конфиг, замените `rsocket:9292` на
`127.0.0.1:9292` и не поднимайте сервис `caddy` из `compose.prod.yaml`.

## Секреты и переменные в GitHub

Настройки репозитория → Settings → Secrets and variables → Actions.
Окружение — `production` (Settings → Environments), workflow выкладки привязан
к нему.

Secrets:

| имя | что кладём |
|---|---|
| `SSH_KEY` | приватный ключ целиком, вместе со строками BEGIN/END |
| `SSH_HOST` | адрес VPS: домен или IP |
| `SSH_USER` | пользователь на VPS, владелец `/srv/rsocket` |

Variables:

| имя | что кладём |
|---|---|
| `SITE_URL` | адрес сайта со схемой, без слеша на конце: `https://rsocket.example.com` |

Публичную половину ключа положите в `~/.ssh/authorized_keys` того же
пользователя на VPS.

## Первая выкладка руками

С машины разработчика, из корня репозитория:

    pnpm --dir web install --frozen-lockfile
    pnpm --dir web build

    ssh <user>@<host> 'mkdir -p /srv/rsocket/releases/manual'
    rsync -az --delete web/dist/ <user>@<host>:/srv/rsocket/releases/manual/

    ssh <user>@<host> '
      cd /srv/rsocket
      ln -sfn /srv/rsocket/releases/manual current.tmp
      mv -T current.tmp current
      cd repo && git pull
      docker compose -p rsocket -f web/infra/compose.prod.yaml up -d --build --wait
    '

`-p rsocket` обязателен. Без него compose берёт имя проекта от каталога файла
(`web/infra` → `infra`) и поднимает рядом второй стек вместо обновления
существующего.

## Проверка

    curl -I  https://<домен>/                 200, Cache-Control: no-cache
    curl -s  https://<домен>/api/health       {"status":"ok", ...}
    curl -I  https://<домен>/lab/что-угодно   200 (SPA-маршрут)
    curl -sI https://<домен>/assets/<файл>    Cache-Control: ... immutable
    curl -o /dev/null -w '%{http_code}\n' -X PUT https://<домен>/api/rules/base.yml   403

Последняя строка важна: запись правил снаружи должна быть закрыта. Чтение
(`GET /api/rules`) при этом работает — витрине оно нужно.

Состояние стека: `docker compose -p rsocket -f web/infra/compose.prod.yaml ps`.

## Дальше — автоматически

Push в `main`, затрагивающий `web/**`, запускает `deploy`: сборка →
rsync в новый `releases/<sha>` → переключение `current` → `git pull` и
`compose up -d --build --wait` на сервере → проверка `/` и `/api/health`.
Если проверка не прошла, симлинк возвращается на предыдущий выпуск, а
workflow краснеет. Хранятся пять последних выпусков; тот, на который смотрит
`current`, и тот, что записан для отката, не удаляются никогда.

## Откат руками

    ssh <user>@<host> '
      cd /srv/rsocket
      ln -sfn "$(cat previous.path)" current.tmp
      mv -T current.tmp current
      readlink -f current
    '

На любой другой выпуск — так же, подставив путь из `ls -1dt /srv/rsocket/releases/*`.
Перезапускать Caddy не нужно: симлинк читается на каждый запрос.

Если испортили правила через `PUT /rules` (изнутри сети — снаружи закрыто),
вернуть их из репозитория: `docker compose -p rsocket -f web/infra/compose.prod.yaml
restart rules`.

## Проверка на машине разработчика

Весь стек поднимается локально, если подставить свой каталог статики и порт.
Домен в `Caddyfile` временно меняется на `:8080`:

    SITE_ROOT=<каталог-родитель> \
      docker compose -p rsocket -f web/infra/compose.prod.yaml up -d

В `SITE_ROOT` должен лежать симлинк `current` на каталог со сборкой.
