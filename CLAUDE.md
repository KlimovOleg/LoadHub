# LoadHub — контекст для Claude

Учебный проект коммерческого уровня: мини-TMS (грузы, водители, диспетчеры, чат, трекинг).
Цель — освоить Laravel 13 + Vue 3 + TypeScript + MariaDB по плану [`docs/laravel_intro2.md`](docs/laravel_intro2.md).
Автор переходит с Yii2: объясняй новые концепции через сравнение с Yii2 и пополняй `docs/yii2-vs-laravel.md`.

**Язык общения и документации — русский.** Код, имена, коммиты — на английском.

## Текущее состояние

- **Этап 0 — выполнен** (2026-09-29): Docker, Laravel 13.34, Sanctum, Pest 5, Larastan (уровень 5), Pint,
  Vue 3 + TS + Vite 8 + Router + Pinia + Vitest, CI. `make init` проверен на чистой копии.
- **Следующий — этап 1** (фундамент Laravel): модели `User`, `Load`, `LoadStop`, `Driver`, `Broker`, `TrailerType`;
  Sanctum SPA-аутентификация; CRUD грузов; сидеры; feature-тесты. См. план, раздел 6, «Этап 1».
- Коммитов ещё нет — первый коммит этапа 0 не сделан.

Обновляй этот раздел при завершении этапа.

## Как работаем по плану

- Каждый этап: **итерация A** (просто, чтобы понять механизм) → **итерация B** (коммерческий уровень).
  Переделки ведутся в `docs/refactoring-debt.md`; этап не закрыт, пока его пункты реестра открыты.
- Не забегай вперёд: не внедряй технологии будущих этапов (Horizon, Reverb, модули, Actions и т. д.),
  пока план до них не дошёл. Если в итерации A пишется «учебный» код — это нормально, он записан в реестре.
- Этап закрывается по чек-боксам «Готово, когда» из плана, а не по календарю.
- Архитектурные решения — ADR в `docs/adr/NNNN-*.md` (следующий номер — 0002).

## Окружение — только Docker

На хосте **нет** PHP, Composer и Node, и ставить их не нужно. Все команды — через `make` или `docker compose exec`:

```bash
make up / down / ps / logs
make sh                                    # shell в контейнере php
docker compose exec php php artisan ...    # artisan
docker compose exec php composer ...       # composer
docker compose exec frontend npm ...       # npm (node_modules собраны под Linux, на Mac не запускать)
make test        # Pest, параллельно, база loadhub_testing
make lint        # Pint --test + Larastan
make fix         # Pint (исправить)
make front-test  # vue-tsc + Vitest
make front-lint  # oxlint + eslint + prettier --check
```

В скриптах и при пайпах добавляй `-T`: `docker compose exec -T php ...`.

Адреса: API http://localhost, фронт http://localhost:5173, Mailpit http://localhost:8025,
MariaDB с хоста `127.0.0.1:3307` (`loadhub`/`secret`; root/`root`).

## Правила, которые нельзя нарушать

- **Тесты — только на MariaDB** (`loadhub_testing`), никогда SQLite. `phpunit.xml` задаёт БД с `force="true"`.
- **Не добавлять `env_file: backend/.env` в docker-compose** — тогда тесты с `RefreshDatabase` сотрут рабочую базу.
  Страховочный тест: `backend/tests/Feature/TestDatabaseTest.php`.
- Хосты в `backend/.env` — имена сервисов compose (`mariadb`, `redis`, `mailpit`), не `127.0.0.1`.
- `docker/mariadb/init.sql` выполняется только при создании volume; изменения — через `down -v` (удаляет данные!)
  или SQL вручную под root. Не делай `down -v` без явного согласия.
- Драйвер БД — `mariadb`, не `mysql`.
- Новые PHP-файлы — с `declare(strict_types=1)` (Pint расставит, arch-тест проверит).
- Перед установкой пакета проверяй поддержку Laravel 13.

## Definition of Done (из плана, раздел 8)

Бэкенд (строго с этапа 3, но стремимся с этапа 1): тонкий контроллер; Form Request на входе, Resource на выходе;
права через Policy + тест на 403; нет N+1; транзакции для изменений нескольких таблиц; обратимые миграции;
`make lint` и `make test` зелёные. Фронтенд (с этапа 6): типы из OpenAPI, без `any`, запросы только через `features/*/api`.

Перед тем как сказать «готово» — запусти `make lint && make test` (и `make front-lint && make front-test`,
если менялся фронт) и приведи результат.

## Документы

| Файл | Что |
|---|---|
| `docs/laravel_intro2.md` | План обучения: этапы, критерии готовности, стандарты кода |
| `docs/install_truble.md` | Ручная установка этапа 0 и все подводные камни |
| `docs/refactoring-debt.md` | Реестр «учебное → коммерческое» |
| `docs/yii2-vs-laravel.md` | Конспект Yii2 → Laravel |
| `docs/adr/` | Архитектурные решения |
