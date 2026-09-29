# LoadHub: ручная установка этапа 0 шаг за шагом (и все подводные камни)

Эта инструкция повторяет ровно то, что было сделано при создании проекта, но руками: каждая команда
для терминала, каждый файл и каждая правка. Подводные камни, на которые реально наткнулись при установке,
отмечены блоком **⚠️ Камень**.

Итог после всех шагов:

| Что | Где |
|---|---|
| Laravel 13 (API) | http://localhost |
| Vue 3 + Vite | http://localhost:5173 |
| Mailpit (перехват почты) | http://localhost:8025 |
| MariaDB с хоста | `127.0.0.1:3307`, пользователь `loadhub` / `secret` |

Все команды выполняются на macOS в `zsh`/`bash`. Отличия для Linux отмечены отдельно.

---

## Содержание

0. [Что нужно на машине](#0-что-нужно-на-машине)
1. [Каталоги проекта](#1-каталоги-проекта)
2. [Файлы Docker-инфраструктуры](#2-файлы-docker-инфраструктуры)
3. [Сборка образа PHP](#3-сборка-образа-php)
4. [Установка Laravel](#4-установка-laravel)
5. [Настройка Laravel под MariaDB, Redis, Mailpit](#5-настройка-laravel-под-mariadb-redis-mailpit)
6. [Запуск бэкенд-сервисов и миграции](#6-запуск-бэкенд-сервисов-и-миграции)
7. [Sanctum (API)](#7-sanctum-api)
8. [Pest вместо PHPUnit, тестовая база](#8-pest-вместо-phpunit-тестовая-база)
9. [Pint и Larastan](#9-pint-и-larastan)
10. [Проверка: тесты не трогают рабочую базу](#10-проверка-тесты-не-трогают-рабочую-базу)
11. [Фронтенд: Vue 3 + TypeScript](#11-фронтенд-vue-3--typescript)
12. [Уборка лишнего в backend](#12-уборка-лишнего-в-backend)
13. [Документация, README, CI](#13-документация-readme-ci)
14. [Финальная проверка «с чистой машины»](#14-финальная-проверка-с-чистой-машины)
15. [Шпаргалка по проблемам](#15-шпаргалка-по-проблемам)

---

## 0. Что нужно на машине

Нужны только **Docker Desktop**, **git** и **make**. PHP, Composer, Node и MariaDB на хосте **не нужны** —
всё запускается в контейнерах.

```bash
docker --version          # Docker 24+ (проверено на 29.4)
docker compose version    # Compose v2 (команда с пробелом, не docker-compose)
git --version
make --version            # на macOS идёт с Xcode Command Line Tools: xcode-select --install
```

Проверьте, свободны ли порты, которые пробрасываются на хост:

```bash
for p in 80 3307 5173 8025; do lsof -nP -iTCP:$p -sTCP:LISTEN | tail -n +2; done
```

Пустой вывод — порты свободны.

> **⚠️ Камень: порт 3306 занят.** На машине работала локальная MariaDB (`mariadbd` на 3306), поэтому
> контейнерная база пробрасывается на **3307**. Все порты вынесены в корневой `.env`, их можно поменять
> без правки compose. Если занят 80 (например, локальный nginx или Valet) — поставьте `APP_PORT=8080`.

Узнайте свой UID и GID, они понадобятся:

```bash
id -u   # на macOS обычно 501
id -g   # на macOS обычно 20 (группа staff)
```

---

## 1. Каталоги проекта

```bash
mkdir -p ~/Php/loadhub
cd ~/Php/loadhub
mkdir -p docker/php docker/nginx docker/mariadb backend frontend docs/adr .github/workflows
git init -b main
```

`backend/` и `frontend/` **должны остаться пустыми** до шагов 4 и 11 — `composer create-project`
отказывается ставить Laravel в непустую папку.

---

## 2. Файлы Docker-инфраструктуры

Создайте файлы ниже любым редактором (PhpStorm, VS Code, `nano`). Путь указан в заголовке.

### 2.1. `.env.example` (в корне — переменные для docker compose)

```dotenv
# Переменные для docker compose (не путать с backend/.env — это настройки Laravel)

# UID/GID пользователя хоста, чтобы файлы из контейнера не принадлежали root.
# make init подставляет их автоматически из `id -u` / `id -g`.
UID=1000
GID=1000

# Порты на хосте
APP_PORT=80
VITE_PORT=5173
DB_FORWARD_PORT=3307
MAILPIT_PORT=8025
```

> **⚠️ Камень: два разных `.env`.** В проекте их два, и путать их нельзя:
> - `./.env` — читает **docker compose** (UID/GID, порты);
> - `./backend/.env` — читает **Laravel** (БД, Redis, почта, ключ приложения).

### 2.2. `docker/php/Dockerfile`

```dockerfile
# ---------- base ----------
FROM php:8.4-fpm-alpine AS base

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions pdo_mysql redis pcntl intl zip gd bcmath opcache exif

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# ---------- dev ----------
FROM base AS dev

RUN install-php-extensions xdebug
COPY ../docker/php/php.ini /usr/local/etc/php/conf.d/99-app.ini

# Пользователь с UID/GID хоста, чтобы файлы в volume не принадлежали root.
# На macOS GID 20 (staff) уже занят в Alpine группой dialout — тогда используем её.
ARG UID=1000
ARG GID=1000
RUN if ! getent group "${GID}" >/dev/null; then addgroup -g "${GID}" app; fi \
 && adduser -D -u "${UID}" -G "$(getent group "${GID}" | cut -d: -f1)" app

USER app

# prod-стадия появится на этапе 9
```

Что здесь важно:
- `install-php-extensions` сам ставит системные зависимости для расширений. Без него пришлось бы
  вручную подбирать `apk add` для `intl`, `gd`, `zip`.
- `pdo_mysql` работает и с MariaDB — отдельного расширения для MariaDB нет.
- В `dev`-стадии процессы запускаются от пользователя с вашим UID, поэтому файлы, которые создают
  `composer` и `artisan`, принадлежат вам, а не root.

> **⚠️ Камень: GID 20 на macOS.** Классический вариант `addgroup -g ${GID} app` падает с
> `addgroup: gid '20' in use`: в Alpine GID 20 уже занят группой `dialout`. Поэтому группа создаётся,
> только если такого GID ещё нет, а иначе пользователь добавляется в существующую группу.

### 2.3. `docker/php/php.ini`

```ini
memory_limit = 512M
upload_max_filesize = 20M
post_max_size = 25M
max_execution_time = 60
date.timezone = UTC
expose_php = Off

; Xdebug выключен по умолчанию. Включить: XDEBUG_MODE=debug в environment сервиса php
; (например, в docker-compose.override.yml) — переменная окружения перекрывает xdebug.mode
xdebug.mode = off
xdebug.client_host = host.docker.internal
xdebug.start_with_request = yes

opcache.enable = 1
opcache.validate_timestamps = 1
opcache.revalidate_freq = 0
```

`opcache.validate_timestamps = 1` и `revalidate_freq = 0` нужны в dev, чтобы изменения в коде
подхватывались сразу. В prod (этап 9) будет наоборот.

### 2.4. `docker/nginx/default.conf`

```nginx
server {
    listen 80;
    server_name localhost;
    root /var/www/html/public;
    index index.php;

    client_max_body_size 25m;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass php:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
```

> **⚠️ Камень: `fastcgi_pass`.** Здесь указывается **имя сервиса из compose** (`php`), а не `127.0.0.1`
> и не `core`, как в первом плане. Если имя не совпадает, nginx отдаёт `502 Bad Gateway`,
> а в `docker compose logs nginx` видно `host not found in upstream`.

### 2.5. `docker/mariadb/init.sql`

```sql
-- Выполняется только при первом создании volume dbdata.
-- MARIADB_USER получает права только на MARIADB_DATABASE, поэтому GRANT на тестовую базу нужен явно.
CREATE DATABASE IF NOT EXISTS loadhub_testing
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Шаблон с % нужен для `php artisan test --parallel`: Laravel создаёт по базе на процесс
-- (loadhub_testing_test_1, loadhub_testing_test_2, ...). `\_` экранирует подчёркивание в шаблоне.
GRANT ALL PRIVILEGES ON `loadhub\_testing%`.* TO 'loadhub'@'%';
FLUSH PRIVILEGES;
```

> **⚠️ Камень 1: права на тестовую базу.** Переменная `MARIADB_USER` в образе MariaDB даёт права
> **только** на базу из `MARIADB_DATABASE` (`loadhub`). Без явного `GRANT` тесты падают с
> `Access denied for user 'loadhub'@'%' to database 'loadhub_testing'`.
>
> **⚠️ Камень 2: параллельные тесты.** `GRANT ... ON loadhub_testing.*` недостаточно:
> `php artisan test --parallel` создаёт отдельную базу на каждый процесс
> (`loadhub_testing_test_1`, `_2`, …, по числу ядер — у меня было 16). Поэтому права выдаются
> по шаблону `` `loadhub\_testing%` ``. Обратные кавычки обязательны, `\_` экранирует подчёркивание:
> в шаблонах `GRANT` символ `_` означает «любой один символ».
>
> **⚠️ Камень 3: скрипт выполняется только один раз** — при первом создании volume `dbdata`.
> Если вы поменяли `init.sql` после первого запуска, изменения **не применятся**. Варианты:
> - `docker compose down -v` — удаляет volume **вместе со всеми данными БД**, затем `docker compose up -d`;
> - либо выполнить SQL вручную под root:
>   ```bash
>   docker compose exec -T mariadb mariadb -uroot -proot < docker/mariadb/init.sql
>   ```

### 2.6. `docker-compose.yml`

```yaml
name: loadhub

x-php: &php
  build:
    context: .
    dockerfile: docker/php/Dockerfile
    target: dev
    args:
      UID: ${UID:-1000}
      GID: ${GID:-1000}
  image: loadhub-php:dev
  # env_file здесь намеренно НЕТ: иначе переменные из backend/.env станут окружением процесса,
  # phpunit.xml не сможет их перекрыть, и тесты пойдут в рабочую базу. Laravel сам читает .env.
  volumes:
    - ./backend:/var/www/html
  extra_hosts:
    - "host.docker.internal:host-gateway"
  depends_on:
    mariadb: { condition: service_healthy }
    redis:   { condition: service_healthy }

services:
  nginx:
    image: nginx:1.27-alpine
    ports: ["${APP_PORT:-80}:80"]
    volumes:
      - ./backend:/var/www/html:ro
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on: [php]

  php:
    <<: *php

  frontend:
    image: node:24.21-alpine   # npm 10 из node:22 падает на зависимостях create-vue ("edgesOut")
    working_dir: /app
    command: sh -c "if [ -f package-lock.json ]; then npm ci; else npm install; fi && npm run dev -- --host 0.0.0.0"
    volumes:
      - ./frontend:/app
    ports: ["${VITE_PORT:-5173}:5173"]

  mariadb:
    image: mariadb:11.4
    environment:
      MARIADB_ROOT_PASSWORD: root
      MARIADB_DATABASE: loadhub
      MARIADB_USER: loadhub
      MARIADB_PASSWORD: secret
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    volumes:
      - dbdata:/var/lib/mysql
      - ./docker/mariadb/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    ports: ["${DB_FORWARD_PORT:-3307}:3306"]   # 3306 на хосте часто занят локальной MariaDB
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 5s
      retries: 20

  redis:
    image: redis:7.4-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      retries: 10

  mailpit:
    image: axllent/mailpit:v1.21
    ports: ["${MAILPIT_PORT:-8025}:8025"]

volumes:
  dbdata:
```

Что здесь важно:
- `name: loadhub` фиксирует имя проекта compose. Контейнеры будут называться `loadhub-php-1` и т. д.
  независимо от имени папки. Побочный эффект: **копия проекта в другой папке использует тот же volume
  `loadhub_dbdata`**, поэтому одновременно две копии запускать нельзя.
- `x-php: &php` — YAML-якорь. На этапе 4 из него же появятся `horizon` и `scheduler`, отличаться будет
  только `command`.
- `depends_on: condition: service_healthy` — PHP стартует только после того, как MariaDB реально
  готова принимать соединения, а не просто запустила процесс. `healthcheck.sh` входит в официальный
  образ MariaDB.
- `extra_hosts: host.docker.internal` нужен для Xdebug на Linux (на macOS работает и без него).

> **⚠️ Камень: `env_file: backend/.env` — САМАЯ опасная ловушка.** Очень хочется передать `.env` Laravel
> в контейнер через `env_file`. Но тогда `DB_DATABASE=loadhub` становится **настоящей переменной окружения
> процесса**. `<env>` в `phpunit.xml` по умолчанию **не перезаписывает** уже существующие переменные,
> и трейт `RefreshDatabase` в тестах выполнит `migrate:fresh` **на рабочей базе** — все данные исчезнут.
> Решение: `env_file` не использовать (Laravel сам читает `backend/.env` из смонтированной папки)
> и дополнительно ставить `force="true"` в `phpunit.xml` (шаг 8.3).

> **⚠️ Камень: Node 22.** Изначально был `node:22-alpine`. Его npm 10.9 падал на `npm install` проекта,
> созданного свежим `create-vue`, с ошибкой
> `npm error Cannot read properties of null (reading 'edgesOut')`. На `node:24-alpine` (npm 11) всё
> ставится. Версия зафиксирована (`24.21`), а не `latest` — так сборка воспроизводима.

> **Linux:** на Linux файлы, которые создаёт контейнер `frontend` (он работает от root), будут принадлежать
> root. Добавьте сервису `frontend` строку `user: "${UID}:${GID}"`. На macOS Docker Desktop сам
> подменяет владельца, там это не нужно.

### 2.7. `Makefile`

> **⚠️ Камень: отступы в Makefile — только табуляция.** Если редактор заменит Tab на пробелы, будет
> `Makefile:NN: *** missing separator. Stop.` В `.editorconfig` (шаг 2.9) для Makefile задан `indent_style = tab`.

```makefile
-include .env

.DEFAULT_GOAL := help
.PHONY: help init env up down restart build sh tinker test lint fix fresh migrate logs ps front-test front-lint

DC      = docker compose
PHP     = $(DC) exec php
ARTISAN = $(PHP) php artisan
FRONT   = $(DC) exec frontend

help: ## Список команд
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

init: env build up ## Первый запуск проекта с нуля
	@[ -f backend/.env ] || cp backend/.env.example backend/.env
	$(PHP) composer install
	@grep -q '^APP_KEY=base64' backend/.env || $(ARTISAN) key:generate
	$(ARTISAN) migrate --seed --force
	@echo ""
	@echo "Готово:"
	@echo "  API     http://localhost:$(or $(APP_PORT),80)"
	@echo "  Фронт   http://localhost:$(or $(VITE_PORT),5173)"
	@echo "  Mailpit http://localhost:$(or $(MAILPIT_PORT),8025)"

env: ## Создать .env для compose с UID/GID текущего пользователя
	@[ -f .env ] || sed -e "s/^UID=.*/UID=$$(id -u)/" -e "s/^GID=.*/GID=$$(id -g)/" .env.example > .env

up: ## Поднять все сервисы
	$(DC) up -d

down: ## Остановить все сервисы
	$(DC) down

restart: down up ## Перезапустить

build: ## Пересобрать образ PHP
	$(DC) build

sh: ## Shell в контейнере PHP
	$(PHP) sh

tinker: ## Laravel Tinker
	$(ARTISAN) tinker

test: ## Тесты бэкенда (на базе loadhub_testing)
	$(ARTISAN) test --parallel

lint: ## Pint (проверка) + Larastan
	$(PHP) ./vendor/bin/pint --test
	$(PHP) ./vendor/bin/phpstan analyse --memory-limit=1G

fix: ## Pint: исправить форматирование
	$(PHP) ./vendor/bin/pint

migrate: ## Применить миграции
	$(ARTISAN) migrate

fresh: ## Пересоздать рабочую БД с тестовыми данными
	$(ARTISAN) migrate:fresh --seed

front-test: ## Тесты фронтенда (Vitest) + проверка типов
	$(FRONT) npm run type-check
	$(FRONT) npm run test:unit:run

front-lint: ## ESLint + Prettier (проверка)
	$(FRONT) npm run lint:check
	$(FRONT) npm run format:check

logs: ## Логи всех сервисов
	$(DC) logs -f --tail=100

ps: ## Статус контейнеров
	$(DC) ps
```

Пояснения:
- `-include .env` подгружает порты из корневого `.env`, чтобы `make init` напечатал правильные адреса.
  Минус в начале означает «не падать, если файла ещё нет».
- В Makefile `$$` — это экранированный `$` для shell. `$$(id -u)` выполнится в shell,
  а `$(PHP)` — это переменная make.
- `key:generate` запускается, только если ключа ещё нет. Иначе повторный `make init` сменил бы
  `APP_KEY`, и все зашифрованные данные и сессии стали бы невалидными.
- `backend/.env` копируется **до** `composer install`. Изначально было наоборот; это работало,
  но скрипты composer (`package:discover`) выполнялись без `.env`.

### 2.8. `.gitignore` (корневой)

```gitignore
# compose-переменные конкретной машины (шаблон — .env.example)
/.env

.DS_Store
.idea/
*.log
```

`backend/` и `frontend/` принесут свои `.gitignore` (для `vendor`, `node_modules`, `backend/.env`).

### 2.9. `.editorconfig`

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
indent_size = 4
indent_style = space
insert_final_newline = true
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false

[*.{yml,yaml,json,ts,js,vue,css}]
indent_size = 2

[Makefile]
indent_style = tab
```

---

## 3. Сборка образа PHP

```bash
make env                 # создаёт ./.env с вашими UID/GID
cat .env                 # проверьте: UID=501, GID=20 (на macOS)
docker compose build     # первая сборка — несколько минут
```

Проверка:

```bash
docker compose run --rm --no-deps php php -v            # PHP 8.4.x
docker compose run --rm --no-deps php php -m | grep -E 'pdo_mysql|redis|intl'
docker compose run --rm --no-deps php id                # uid=501(app) ...
```

`--no-deps` нужен, чтобы вместе с одноразовым контейнером не поднимались mariadb и redis.
`--rm` удаляет контейнер после выполнения.

---

## 4. Установка Laravel

```bash
docker compose run --rm --no-deps php composer create-project laravel/laravel . --prefer-dist --no-interaction
docker compose run --rm --no-deps php php artisan --version   # Laravel Framework 13.x
```

Точка в конце `create-project` означает «ставить в текущую папку контейнера» — это `/var/www/html`,
то есть смонтированный `backend/`.

> **⚠️ Камень: папка должна быть пустой.** Даже `.gitkeep` в `backend/` приведёт к ошибке
> `Project directory "/var/www/html/." is not empty`.

> **⚠️ Камень: скелет по умолчанию на SQLite.** Скрипт `post-create-project-cmd` создал
> `database/database.sqlite` и прогнал в него миграции. Нам SQLite не нужен — удаляем:
>
> ```bash
> rm -f backend/database/database.sqlite
> ```

---

## 5. Настройка Laravel под MariaDB, Redis, Mailpit

Отредактируйте **оба** файла — `backend/.env.example` (шаблон для других разработчиков и CI)
и `backend/.env` (ваш рабочий). Замены одинаковые:

| Было | Стало |
|---|---|
| `APP_NAME=Laravel` | `APP_NAME=LoadHub` |
| `APP_URL=http://localhost:8000` | `APP_URL=http://localhost` |
| блок `DB_CONNECTION=sqlite` и закомментированные `# DB_...` | см. ниже |
| `REDIS_HOST=127.0.0.1` | `REDIS_HOST=redis` |
| `MAIL_MAILER=log` | `MAIL_MAILER=smtp` |
| `MAIL_HOST=127.0.0.1` | `MAIL_HOST=mailpit` |
| `MAIL_PORT=2525` | `MAIL_PORT=1025` |
| `MAIL_FROM_ADDRESS="hello@example.com"` | `MAIL_FROM_ADDRESS="noreply@loadhub.local"` |

Блок базы данных:

```dotenv
# Хосты — имена сервисов docker compose, а не 127.0.0.1
DB_CONNECTION=mariadb
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=loadhub
DB_USERNAME=loadhub
DB_PASSWORD=secret
```

> **⚠️ Камень: `127.0.0.1` внутри контейнера — это сам контейнер.** PHP работает в своём контейнере,
> и `127.0.0.1` указывает на него же, а не на MariaDB. Хост — всегда **имя сервиса** из compose
> (`mariadb`, `redis`, `mailpit`). Порт — **внутренний** (3306), а не проброшенный на хост (3307).
> Порт 3307 нужен только для подключения с вашего Mac (DataGrip, TablePlus).

> **⚠️ Камень: драйвер `mariadb`, а не `mysql`.** В Laravel 11+ для MariaDB есть отдельный драйвер.
> С `mysql` всё почти работает, но грамматика запросов отличается в деталях.

Mailpit принимает SMTP на порту **1025**, а веб-интерфейс у него на **8025**. Не путайте.

`SESSION_DRIVER`, `CACHE_STORE` и `QUEUE_CONNECTION` остаются `database` — это учебная итерация A
(реестр п. 7 и 14, переделка на этапах 4 и 7).

---

## 6. Запуск бэкенд-сервисов и миграции

```bash
docker compose up -d mariadb redis mailpit php nginx
docker compose ps                        # mariadb и redis должны быть (healthy)
docker compose exec php php artisan migrate --force
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/      # 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/up    # 200 — встроенный health-check Laravel
```

Проверьте права пользователя БД — должно быть три строки GRANT:

```bash
docker compose exec mariadb mariadb -uloadhub -psecret -e "SHOW GRANTS"
```

```
GRANT USAGE ON *.* TO `loadhub`@`%` ...
GRANT ALL PRIVILEGES ON `loadhub`.* TO `loadhub`@`%`
GRANT ALL PRIVILEGES ON `loadhub\_testing%`.* TO `loadhub`@`%`
```

Проверьте, что параллельные тестовые базы создаются:

```bash
docker compose exec mariadb mariadb -uloadhub -psecret \
  -e "CREATE DATABASE loadhub_testing_test_1; DROP DATABASE loadhub_testing_test_1; SELECT 'ok';"
```

Если третьей строки GRANT нет — см. «Камень 3» в разделе 2.5.

> **Когда нужен `-T`.** `docker compose exec` по умолчанию выделяет TTY. В скриптах, в CI и при
> перенаправлении вывода (`| grep`, `< file.sql`) добавляйте `-T`: `docker compose exec -T php ...`.
> Иначе будет ошибка `the input device is not a TTY`.

---

## 7. Sanctum (API)

```bash
docker compose exec php php artisan install:api --no-interaction
```

Команда ставит `laravel/sanctum`, создаёт `routes/api.php` и миграцию `personal_access_tokens` и
сразу её применяет. В конце она пишет:
`Please add the [Laravel\Sanctum\HasApiTokens] trait to your User model.` — это нужно сделать руками.

Файл `backend/app/Models/User.php` — добавьте импорт и трейт:

```php
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;          // ← добавить

// ...
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;   // ← добавить HasApiTokens
```

Проверка — API без авторизации должен отвечать `401`:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H "Accept: application/json" http://localhost/api/user   # 401
```

> Без заголовка `Accept: application/json` Laravel попытается перенаправить на страницу логина
> и ответит `500` (роута `login` нет). Для API всегда отправляйте `Accept: application/json`.

---

## 8. Pest вместо PHPUnit, тестовая база

### 8.1. Установка

```bash
docker compose exec php composer remove phpunit/phpunit --dev --no-interaction
docker compose exec php composer require pestphp/pest pestphp/pest-plugin-laravel larastan/larastan --dev -W --no-interaction
docker compose exec php ./vendor/bin/pest --version     # Pest 5.x
```

> **⚠️ Камень: сначала удалить phpunit.** Pest сам тянет нужную ему версию PHPUnit. Если оставить
> в `composer.json` явное требование `phpunit/phpunit`, composer может не найти совместимую
> комбинацию версий. `-W` (`--with-all-dependencies`) разрешает обновить зависимости зависимостей.

### 8.2. Структура тестов

Удалите стандартные примеры PHPUnit и создайте папки:

```bash
rm backend/tests/Feature/ExampleTest.php backend/tests/Unit/ExampleTest.php
touch backend/tests/Unit/.gitkeep
mkdir -p backend/tests/Arch
```

**`backend/tests/Pest.php`**

```php
<?php

declare(strict_types=1);

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/*
|--------------------------------------------------------------------------
| Test Case
|--------------------------------------------------------------------------
|
| Feature-тесты работают с полноценным приложением и реальной MariaDB
| (база loadhub_testing, см. phpunit.xml). SQLite не используем намеренно.
|
*/

pest()->extend(TestCase::class)
    ->use(RefreshDatabase::class)
    ->in('Feature');

pest()->extend(TestCase::class)
    ->in('Unit');
```

**`backend/tests/Feature/TestDatabaseTest.php`** — страховочный тест от главной ловушки:

```php
<?php

declare(strict_types=1);

use Illuminate\Support\Facades\DB;

// Страховка от ловушки «тесты стёрли рабочую базу»: RefreshDatabase
// не должен никогда запускаться на loadhub.
it('runs tests against the dedicated MariaDB test database', function (): void {
    expect(DB::connection()->getDriverName())->toBe('mariadb')
        ->and(DB::connection()->getDatabaseName())->toStartWith('loadhub_testing');
});
```

`toStartWith`, а не `toBe`: при `--parallel` база называется `loadhub_testing_test_N`.

**`backend/tests/Feature/HealthTest.php`**

```php
<?php

declare(strict_types=1);

it('responds on the health check endpoint', function (): void {
    $this->get('/up')->assertOk();
});

it('rejects unauthenticated api requests with json 401', function (): void {
    $this->getJson('/api/user')->assertUnauthorized();
});
```

**`backend/tests/Arch/ArchTest.php`**

```php
<?php

declare(strict_types=1);

// Базовые архитектурные правила. На этапе 3 сюда добавятся правила границ модулей.

arch('no debugging functions are left in code')
    ->expect(['dd', 'dump', 'ddd', 'ray', 'var_dump', 'print_r'])
    ->not->toBeUsed();

arch('app code uses strict types')
    ->expect('App')
    ->toUseStrictTypes();

arch()->preset()->security();
```

### 8.3. `backend/phpunit.xml`

Внесите три правки.

**1)** Добавьте тестовый набор `Arch` после `Feature`:

```xml
        <testsuite name="Feature">
            <directory>tests/Feature</directory>
        </testsuite>
        <testsuite name="Arch">
            <directory>tests/Arch</directory>
        </testsuite>
```

**2)** Строку `APP_ENV` сделайте принудительной:

```xml
        <!-- force="true": переменные окружения контейнера не должны перекрыть тестовую БД -->
        <env name="APP_ENV" value="testing" force="true"/>
```

**3)** Замените две строки SQLite

```xml
        <env name="DB_CONNECTION" value="sqlite"/>
        <env name="DB_DATABASE" value=":memory:"/>
```

на

```xml
        <env name="DB_CONNECTION" value="mariadb" force="true"/>
        <env name="DB_DATABASE" value="loadhub_testing" force="true"/>
```

Остальные `<env>` (`CACHE_STORE=array`, `QUEUE_CONNECTION=sync`, `MAIL_MAILER=array` и т. д.) оставьте как есть.

> **⚠️ Камень: почему `force="true"`.** Это вторая линия защиты от ловушки из раздела 2.6. Даже если
> кто-то однажды добавит `env_file` в compose или задаст `DB_DATABASE` в окружении CI, тесты всё равно
> пойдут в `loadhub_testing`. Без `force` PHPUnit молча оставит уже существующую переменную.

> **Почему не SQLite in-memory, как в скелете Laravel.** SQLite ведёт себя иначе там, где это важно
> для проекта: `lockForUpdate` фактически ничего не блокирует, `whereFullText` не поддерживается,
> иначе работают JSON и строгость типов. Тесты были бы зелёными на SQLite и красными на MariaDB.

---

## 9. Pint и Larastan

**`backend/pint.json`**

```json
{
    "preset": "laravel",
    "rules": {
        "declare_strict_types": true,
        "final_class": false,
        "fully_qualified_strict_types": true,
        "global_namespace_import": {
            "import_classes": true,
            "import_constants": false,
            "import_functions": false
        },
        "strict_comparison": true
    }
}
```

**`backend/phpstan.neon`**

```neon
includes:
    - vendor/larastan/larastan/extension.neon

parameters:
    paths:
        - app/
        - config/
        - database/
        - routes/

    # Этап 0: уровень 5. План подъёма: 6 на этапе 3, 8 на этапе 7 (реестр, п. 15).
    level: 5

    tmpDir: storage/framework/cache/phpstan
```

`tmpDir` внутри `storage/` — кеш анализа хранится в смонтированной папке проекта и переживает
пересоздание контейнера, поэтому повторные запуски Larastan быстрее. `storage/framework/cache`
уже в `.gitignore` Laravel.

Запуск — **строго в этом порядке**:

```bash
make fix     # 1. Pint расставит declare(strict_types=1) во все файлы скелета Laravel
make lint    # 2. Pint --test + Larastan: [OK] No errors
make test    # 3. 6 passed
```

> **⚠️ Камень: порядок важен.** Тест `app code uses strict types` падает на свежем скелете Laravel:
> в файлах `app/` нет `declare(strict_types=1)`. Их добавляет Pint по правилу `declare_strict_types`.
> Если запустить тесты до `make fix`, получите красный arch-тест, хотя в коде ничего не сломано.

> **⚠️ Камень: `declare(strict_types=1)` меняет поведение.** Раньше `strlen(123)` молча приводил
> число к строке, а теперь бросает `TypeError`. Для скелета Laravel это безопасно (проверено тестами
> и Larastan), но в чужом legacy-коде такое правило может «сломать» вызовы, которые раньше работали.

---

## 10. Проверка: тесты не трогают рабочую базу

Главный критерий этапа 0 — проверить руками:

```bash
docker compose exec php php artisan db:seed --force      # создаст тестового пользователя в рабочей БД
docker compose exec -T mariadb mariadb -uloadhub -psecret loadhub -N -e "select count(*) from users"   # 1
make test                                                 # параллельно, 16 процессов
docker compose exec -T mariadb mariadb -uloadhub -psecret loadhub -N -e "select count(*) from users"   # всё ещё 1
```

Если после `make test` получилось `0` — где-то утекла переменная `DB_DATABASE`: проверьте раздел 2.6
(`env_file`) и раздел 8.3 (`force="true"`).

---

## 11. Фронтенд: Vue 3 + TypeScript

### 11.1. Создание проекта

Очевидный вариант **не работает**:

```bash
# ✗ НЕ РАБОТАЕТ
docker compose run --rm --no-deps frontend npm create vue@latest .
```

> **⚠️ Камень 1: `docker compose up frontend` с пустой папкой не работает.** Его `command` сразу
> запускает `npm install && npm run dev`, а `package.json` ещё нет — контейнер падает. Поэтому проект
> создаётся через `docker compose run ... <своя команда>`: явная команда заменяет `command` из compose.
>
> **⚠️ Камень 2: `create-vue` в папке `.` задаёт интерактивный вопрос** `Package name:`, даже если
> все остальные флаги переданы, и без терминала зависает на нём.

Рабочий вариант — создать проект во временной папке контейнера и скопировать в `/app`:

```bash
docker compose run --rm --no-deps frontend sh -c "\
  cd /tmp && \
  npm create vue@latest loadhub-frontend -- --ts --router --pinia --vitest --eslint --prettier --force && \
  cp -a loadhub-frontend/. /app/"
```

- `--` отделяет аргументы для `create-vue` от аргументов самого `npm`.
- Флаги отвечают на все вопросы мастера: TypeScript, Router, Pinia, Vitest, ESLint, Prettier.
- `cp -a loadhub-frontend/.` (с точкой) копирует и скрытые файлы — `.gitignore`, `.prettierrc.json`,
  `.editorconfig`, `.oxlintrc.json`. Вариант `cp -a loadhub-frontend/* /app/` их бы потерял.

Если хотите пройти мастер интерактивно — запустите без флагов и ответьте на вопросы. Главное —
создавать проект не в `.`.

Проверьте, что появились `frontend/package.json`, `frontend/vite.config.ts`, `frontend/src/`.

### 11.2. `frontend/vite.config.ts` — настройка dev-сервера для Docker

Добавьте блок `server` перед `resolve`:

```ts
  // Dev-сервер в Docker: слушаем все интерфейсы, порт фиксирован (он проброшен в compose)
  server: {
    host: '0.0.0.0',
    port: 5173,
    strictPort: true,
  },
  resolve: {
```

> **⚠️ Камень: `host`.** По умолчанию Vite слушает только `localhost` **внутри контейнера**, и с Mac
> страница не открывается (`ERR_EMPTY_RESPONSE`). Нужно `0.0.0.0`. `strictPort: true` не даёт Vite
> молча уйти на 5174, если 5173 занят: проброшен-то только 5173.

### 11.3. `frontend/package.json` — скрипты для проверок

Сгенерированные скрипты `lint` и `format` **исправляют** файлы (`--fix`, `--write`). Для CI и `make`
нужны версии, которые только проверяют. Добавьте в `"scripts"` три строки:

```json
    "test:unit:run": "vitest --run",
    "lint:check": "oxlint . && eslint .",
    "format:check": "prettier --check src/"
```

- `vitest` без `--run` работает в watch-режиме и никогда не завершится — в CI это зависание.
- `lint:check` без `--fix`: в CI проверка не должна менять код.

### 11.4. Первый запуск

```bash
docker compose up -d frontend
docker compose logs -f frontend         # ждём "VITE v8.x ready", выход — Ctrl+C
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5173/   # 200
```

Первый старт делает `npm install` и создаёт `package-lock.json`. Все последующие запуски используют
`npm ci`: он быстрее и ставит ровно то, что записано в lock-файле.

> **⚠️ Камень: `npm ci` без lock-файла.** `npm ci` падает, если нет `package-lock.json`. Поэтому
> в `command` стоит проверка: если lock-файл есть — `npm ci`, иначе `npm install`.

> **⚠️ Камень: ошибка `edgesOut` на Node 22.** Если видите
> `npm error Cannot read properties of null (reading 'edgesOut')` — это npm 10 из `node:22`.
> Смените образ на `node:24.21-alpine` (раздел 2.6), удалите `frontend/node_modules`
> и перезапустите: `docker compose up -d --force-recreate frontend`.

Отформатируйте сгенерированный код (Prettier может не согласиться с шаблоном `create-vue`) и
прогоните все проверки:

```bash
docker compose exec frontend npm run format
make front-lint                                   # oxlint + eslint + prettier --check
make front-test                                   # vue-tsc + vitest
docker compose exec frontend npm run build-only   # продакшен-сборка собирается
```

> **⚠️ Камень: `node_modules` собраны под Linux.** Пакеты с нативными бинарниками (oxlint, rolldown
> в Vite 8, esbuild) установлены в контейнере в сборке для Linux/musl. Если запустить `npm run dev`
> прямо на Mac, будет ошибка вида `Cannot find module '@oxlint/darwin-arm64'`. Все npm-команды —
> через контейнер: `docker compose exec frontend npm ...`. Если очень нужно запускать на хосте — удалите
> `node_modules` и сделайте `npm ci` на хосте, но тогда перестанет работать контейнер. Одновременно
> и там, и там не получится.

---

## 12. Уборка лишнего в backend

Скелет Laravel содержит свою Vite-обвязку для Blade-шаблонов. У нас фронт — отдельное SPA, а два
`package.json` в проекте только путают. Удаляем:

```bash
rm -f backend/package.json backend/vite.config.js
rm -rf backend/resources/css backend/resources/js
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/    # всё ещё 200
```

Приветственная страница `welcome.blade.php` продолжит работать: у неё есть встроенные стили на случай,
если Vite-сборки нет (`@if (file_exists(public_path('build/manifest.json')) ...)`).

Удалите также `backend/AGENTS.md` и `backend/CLAUDE.md`:

```bash
rm backend/AGENTS.md backend/CLAUDE.md
```

> **⚠️ Камень: инструкции для ИИ из скелета Laravel 13.** Эти файлы — подсказки для ИИ-ассистентов
> (Claude Code, Cursor и т. п.). Они велят поставить PHP 8.5 прямо на хост через `php.new` и установить
> Laravel Boost. В нашей схеме «всё в Docker» это вредно: ассистент начнёт ставить PHP на Mac.
> Вместо них в корне проекта лежит свой `CLAUDE.md` с правилами проекта: только Docker, тесты на
> MariaDB, текущий этап плана.

---

## 13. Документация, README, CI

### 13.1. Документы

Создайте:
- `docs/adr/0001-mariadb-own-docker-spa.md` — ADR: контекст, решение (MariaDB, свой Docker, SPA), последствия;
- `docs/laravel_intro2.md` — план обучения (копия из gLogic);
- `docs/install_truble.md` — эта инструкция;
- `docs/refactoring-debt.md` — реестр «учебное → коммерческое» из `docs/laravel_intro2.md` с колонкой «Статус»;
- `docs/yii2-vs-laravel.md` — таблица соответствий и записи в формате «Yii2 → Laravel → подвох»;
- `README.md` — стек, быстрый старт, команды, структура, ловушки.

Готовые версии этих файлов уже лежат в проекте — используйте их как образец.

### 13.2. `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  backend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend

    services:
      mariadb:
        image: mariadb:11.4
        env:
          MARIADB_ROOT_PASSWORD: root
          MARIADB_DATABASE: loadhub_testing
          MARIADB_USER: loadhub
          MARIADB_PASSWORD: secret
        ports: ["3306:3306"]
        options: >-
          --health-cmd="healthcheck.sh --connect --innodb_initialized"
          --health-interval=5s --health-retries=20
      redis:
        image: redis:7.4-alpine
        ports: ["6379:6379"]

    env:
      DB_HOST: 127.0.0.1
      DB_USERNAME: loadhub
      DB_PASSWORD: secret
      REDIS_HOST: 127.0.0.1

    steps:
      - uses: actions/checkout@v4

      - uses: shivammathur/setup-php@v2
        with:
          php-version: "8.4"
          extensions: pdo_mysql, redis, intl, zip, gd, bcmath, exif
          coverage: none

      - name: Cache Composer
        uses: actions/cache@v4
        with:
          path: ~/.composer/cache
          key: composer-${{ hashFiles('backend/composer.lock') }}

      - run: composer install --no-interaction --prefer-dist --no-progress
      - run: cp .env.example .env && php artisan key:generate

      - name: Pint
        run: ./vendor/bin/pint --test

      - name: Larastan
        run: ./vendor/bin/phpstan analyse --memory-limit=1G --no-progress

      # Без --parallel: пользователь CI имеет права только на loadhub_testing,
      # а параллельный режим создаёт loadhub_testing_test_N.
      - name: Tests
        run: php artisan test

  frontend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: frontend

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "24"
          cache: npm
          cache-dependency-path: frontend/package-lock.json

      - run: npm ci
      - run: npm run lint:check
      - run: npm run format:check
      - run: npm run type-check
      - run: npm run test:unit:run
      - run: npm run build-only
```

Отличия CI от локального окружения, о которых стоит помнить:
- **В CI нет docker compose.** PHP ставится прямо на раннер, а MariaDB и Redis запускаются как
  `services`. Поэтому хост там `127.0.0.1`, а не `mariadb`. Он передаётся через `env:` на уровне
  задачи, а реальные переменные окружения важнее значений из `.env`.
- **`init.sql` в CI не выполняется**, поэтому `MARIADB_DATABASE` сразу `loadhub_testing`, и тесты
  идут без `--parallel` (прав на `loadhub_testing_test_N` там нет).
- `DB_DATABASE` в CI задавать не нужно: `phpunit.xml` с `force="true"` всё равно выставит `loadhub_testing`.

> CI заработает после того, как вы создадите репозиторий на GitHub и сделаете `git push`.
> Локально проверить workflow можно утилитой `act`, но это необязательно.

---

## 14. Финальная проверка «с чистой машины»

Критерий этапа 0: `git clone && make init` поднимает всё на чистой машине. Проверить это можно без
второго компьютера — скопировать только те файлы, которые попадут в git, и поднять копию.

```bash
cd ~/Php/loadhub
docker compose down -v                         # ⚠️ удалит данные БД текущего стенда

CLEAN=/tmp/loadhub-clean
rm -rf $CLEAN && mkdir -p $CLEAN
git ls-files --others --cached --exclude-standard -z | rsync -a --from0 --files-from=- ./ $CLEAN/

# в копии не должно быть того, что не коммитится:
ls $CLEAN/backend/vendor $CLEAN/frontend/node_modules $CLEAN/.env $CLEAN/backend/.env 2>&1 | grep -c "No such"   # 4

cd $CLEAN
make init
make test && make lint && make front-test && make front-lint
for u in http://localhost/ http://localhost/up http://localhost:5173/ http://localhost:8025/; do
  curl -s -o /dev/null -w "$u %{http_code}\n" $u
done

docker compose down -v                         # убрать тестовый стенд
cd ~/Php/loadhub && rm -rf $CLEAN && make init # вернуть основной
```

> **⚠️ Камень: две копии одновременно.** Из-за `name: loadhub` в compose копия и оригинал используют
> одни и те же имена контейнеров и volume. Сначала остановите оригинал (`docker compose down -v`),
> потом поднимайте копию, и наоборот.

> `git ls-files --others --cached --exclude-standard` выводит все файлы, которые **не** игнорируются
> `.gitignore`: и уже закоммиченные, и новые. Это ровно то, что получит человек после `git clone`.

Ожидаемый результат: 6 контейнеров `Up`, все четыре URL отвечают `200`, все четыре `make`-проверки зелёные.

Когда всё проверено — первый коммит:

```bash
git add -A
git status            # убедитесь, что нет vendor/, node_modules/, .env, backend/.env
git commit -m "chore: stage 0 — docker, laravel 13, vue 3, tests, ci"
```

---

## 15. Шпаргалка по проблемам

| Симптом | Причина | Решение |
|---|---|---|
| `Bind for 0.0.0.0:3306 failed: port is already allocated` | Порт занят локальной MariaDB/MySQL | Порт в `.env`: `DB_FORWARD_PORT=3307` |
| `addgroup: gid '20' in use` при сборке | На macOS GID 20 занят в Alpine группой `dialout` | Dockerfile из раздела 2.2 (создавать группу, только если её нет) |
| `Project directory ... is not empty` | В `backend/` есть файлы (даже `.gitkeep`) | Очистить `backend/` перед `create-project` |
| `SQLSTATE[HY000] [2002] Connection refused` | В `backend/.env` стоит `DB_HOST=127.0.0.1` | `DB_HOST=mariadb` |
| `SQLSTATE[HY000] [2002] php_network_getaddresses` | Контейнер `mariadb` не запущен или ещё не healthy | `docker compose ps`, подождать `(healthy)` |
| `Access denied ... to database 'loadhub_testing'` | Нет GRANT на тестовую базу | Раздел 2.5; если volume уже был — `down -v` или GRANT вручную |
| `Access denied ... 'loadhub_testing_test_1'` при `--parallel` | GRANT только на `loadhub_testing`, без шаблона | `` GRANT ... ON `loadhub\_testing%`.* `` |
| Поменял `init.sql`, ничего не изменилось | Скрипт выполняется только при создании volume | `docker compose down -v` или SQL вручную под root |
| **После тестов рабочая база пустая** | `env_file` в compose и/или нет `force="true"` | Разделы 2.6 и 8.3, тест `TestDatabaseTest` |
| `502 Bad Gateway` от nginx | `fastcgi_pass` указывает не на тот сервис или php не запущен | `fastcgi_pass php:9000;`, `docker compose ps` |
| `/api/user` отвечает `500` вместо `401` | Запрос без `Accept: application/json`, Laravel ищет роут `login` | Отправлять заголовок `Accept: application/json` |
| Arch-тест `uses strict types` красный | Pint ещё не расставил `declare(strict_types=1)` | `make fix`, потом `make test` |
| composer: `Your requirements could not be resolved` при установке Pest | Мешает явный `phpunit/phpunit` в require-dev | Сначала `composer remove phpunit/phpunit --dev`, потом `require ... -W` |
| `create-vue` зависает на `Package name:` | Создание в папке `.` | Создать в `/tmp/имя` и скопировать (раздел 11.1) |
| `npm error ... reading 'edgesOut'` | npm 10 в `node:22` | Образ `node:24.21-alpine` |
| `npm ci` — `can only install with an existing package-lock.json` | Первый запуск, lock-файла ещё нет | `command` с проверкой (раздел 2.6) |
| Vite с Mac не открывается, в контейнере работает | Vite слушает только localhost контейнера | `server.host: '0.0.0.0'` (раздел 11.2) |
| `Cannot find module '@oxlint/darwin-arm64'` или `@rolldown/...` | `npm` запущен на Mac, а `node_modules` — под Linux | Запускать через `docker compose exec frontend npm ...` |
| `Makefile: *** missing separator` | Отступы пробелами вместо Tab | Tab в Makefile, `.editorconfig` |
| `the input device is not a TTY` | `docker compose exec` в скрипте или с пайпом | Добавить `-T` |
| `sed: 1: "...": bad flag in substitute command` | BSD `sed` на macOS: разделитель `#` встретился в заменяемом тексте, или не указан `''` после `-i` | Редактировать файл в редакторе; на macOS — `sed -i '' 's|a|b|' file` с разделителем, которого нет в тексте |
| Файлы в `frontend/` принадлежат root (только Linux) | Контейнер node работает от root | `user: "${UID}:${GID}"` у сервиса `frontend` |
| Порт 80 занят | Локальный nginx/Apache/Valet | `APP_PORT=8080` в `.env`, открыть `http://localhost:8080` |

---

## Итоговые версии (на момент установки)

| Компонент | Версия |
|---|---|
| PHP | 8.4 (php:8.4-fpm-alpine) |
| Laravel | 13.34 |
| Pest | 5.2 |
| Larastan | 3.12 |
| MariaDB | 11.4 LTS |
| Redis | 7.4 |
| nginx | 1.27 |
| Node / npm | 24.21 / 11.19 |
| Vue / Vite / TypeScript | 3.5 / 8 / 6.0 |
| Pinia / Vue Router | 4 / 5 |
| Vitest | 4 |
