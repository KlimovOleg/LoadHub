# LoadHub

Учебный проект коммерческого уровня: мини-TMS (грузы, водители, диспетчеры) на Laravel 13 + Vue 3 + MariaDB.
План обучения — [`docs/laravel_intro2.md`](docs/laravel_intro2.md). Текущий этап: **0 — окружение и скелет**.
Ручная установка с нуля и все подводные камни — [`docs/install_truble.md`](docs/install_truble.md).

## Стек

| Часть | Технологии |
|---|---|
| Бэкенд | PHP 8.4, Laravel 13, Sanctum, Pest 5, Larastan, Pint |
| БД / кеш | MariaDB 11.4 LTS, Redis 7.4 |
| Фронтенд | Vue 3, TypeScript, Vite, Vue Router, Pinia, Vitest, ESLint + Oxlint, Prettier |
| Инфраструктура | Docker Compose, nginx, Mailpit, GitHub Actions |

## Быстрый старт

Нужен только Docker. PHP, Composer, Node и MariaDB на хосте не нужны.

```bash
git clone <repo> loadhub && cd loadhub
make init
```

| Сервис | Адрес |
|---|---|
| API (Laravel) | http://localhost |
| Фронт (Vite) | http://localhost:5173 |
| Mailpit | http://localhost:8025 |
| MariaDB с хоста | `127.0.0.1:3307`, `loadhub` / `secret` |

Порты меняются в `.env` в корне (создаётся из `.env.example` командой `make env`).

## Команды

```bash
make help        # все команды
make up / down   # поднять / остановить
make sh          # shell в контейнере PHP
make test        # тесты бэкенда (база loadhub_testing, параллельно)
make lint        # Pint (проверка) + Larastan
make fix         # Pint: исправить форматирование
make fresh       # пересоздать рабочую БД с сидерами
make front-test  # vue-tsc + Vitest
make front-lint  # Oxlint + ESLint + Prettier (проверка)
```

npm-команды выполняйте в контейнере: `docker compose exec frontend npm <команда>`.
`node_modules` собраны под Linux (musl) и на macOS напрямую не запустятся.

## Структура

```
loadhub/
├── Makefile                 # единая точка входа
├── docker-compose.yml
├── .env.example             # переменные compose: UID/GID, порты
├── docker/
│   ├── php/Dockerfile       # base → dev (prod появится на этапе 9)
│   ├── php/php.ini
│   ├── nginx/default.conf
│   └── mariadb/init.sql     # тестовые БД + GRANT
├── backend/                 # Laravel 13 (API)
├── frontend/                # Vue 3 + TS (SPA)
├── docs/
│   ├── adr/                 # архитектурные решения
│   ├── laravel_intro2.md    # план обучения
│   ├── install_truble.md    # ручная установка этапа 0 + подводные камни
│   ├── refactoring-debt.md  # реестр «учебное → коммерческое»
│   └── yii2-vs-laravel.md   # личный конспект
└── .github/workflows/ci.yml
```

## Важно знать

- **Тесты никогда не идут в рабочую базу.** `phpunit.xml` задаёт `DB_DATABASE=loadhub_testing` с `force="true"`,
  а `backend/.env` намеренно не передаётся в контейнер через `env_file`. Тест `TestDatabaseTest` это проверяет.
- **`docker/mariadb/init.sql` выполняется только при первом создании volume.** Если изменили его —
  `docker compose down -v` (данные БД удалятся) и `make init`.
- **Xdebug** выключен. Включить: `XDEBUG_MODE=debug` в `environment` сервиса `php`
  (удобно через `docker-compose.override.yml`).
