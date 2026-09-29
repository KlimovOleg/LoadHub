# План освоения Laravel 13 + Vue 3 (вариант 2: быстрее и практичнее)

> Исходные данные: опыт на Yii2 (очереди, RabbitMQ, сокеты, сессии, кеш), рабочая БД — MariaDB.
> Цель: за **~15 недель** выйти на уверенный коммерческий уровень Laravel 13 + Vue 3 + TypeScript,
> ещё за **~5 недель** освоить RabbitMQ, микросервисы и продакшен.
> Темп: 3–4 часа в день, 5–6 дней в неделю.

---

## 1. Чем этот план отличается от первого

| Было | Стало | Почему |
|---|---|---|
| Всё коммерческое с первого дня | **Сначала просто → потом переделка под коммерческий уровень** | Нельзя качественно отрефакторить то, чего ещё не понимаешь. Сама переделка учит лучше всего: видно, зачем нужен каждый слой |
| 13 контейнеров в первую неделю | 6 контейнеров, остальные добавляются по мере надобности | Меньше времени на инфраструктуру и больше на Laravel |
| PostgreSQL | **MariaDB 11.4 LTS** | Ваш рабочий стек, знания сразу пригодятся |
| HelpDesk | **Мини-TMS «LoadHub»** (грузы, водители, диспетчеры) | Знакомый домен: не тратите силы на предметную область, и опыт потом переносится на gLogic |
| Vue и бэкенд перегружали одни и те же недели | Чередование: неделя бэкенда → блок фронта, без двойной нагрузки | Реалистичная нагрузка |
| Larastan 8 и покрытие 80% на 5-й неделе | Larastan 5 → 6 → 8 постепенно, покрытие растёт вместе с кодом | Качество растёт, а не тормозит обучение |
| Микросервисы — обязательная часть | Ядро (недели 1–15) + расширение (недели 16–20) | После 15-й недели вы уже коммерчески полезны, остальное — рост |

---

## 2. Главное правило: «просто → коммерчески»

Каждую технологию проходим в два шага:

1. **Итерация A (учебная).** Делаем максимально прямолинейно, по документации, чтобы понять механизм.
2. **Итерация B (коммерческая).** Переделываем по стандартам production-кода. Итерация B **обязательна**: этап не закрыт, пока все его пункты из таблицы ниже не переделаны.

### 2.1. Реестр «учебное → коммерческое» (чек-лист переделок)

Этот список — ваш технический долг. Ведите его в `docs/refactoring-debt.md` и закрывайте пункты по мере прохождения этапов.

| # | Учебный вариант (A) | Коммерческий вариант (B) | Этап переделки |
|---|---|---|---|
| 1 | `$request->validate()` в контроллере | Form Request классы | 1 |
| 2 | Возврат моделей из контроллера | API Resources, единый формат ответа и ошибок | 1 |
| 3 | Логика в контроллере | Action-классы + DTO, тонкие контроллеры | 3 |
| 4 | Статусы строками | PHP enum + явная машина переходов состояний | 3 |
| 5 | Роль — колонка `role` в `users` | spatie/laravel-permission + Policies | 3 |
| 6 | Стандартная структура `app/Models`, `app/Http` | Модули `app/Modules/*` + архитектурные тесты | 3 |
| 7 | Очередь `database` | Redis + Horizon, раздельные очереди по приоритетам | 4 |
| 8 | Синхронная отправка уведомлений | Уведомления через очередь, ретраи, идемпотентность | 4 |
| 9 | Файлы на локальном диске | S3 (MinIO), подписанные временные ссылки | 4 |
| 10 | `fetch`/`axios` прямо в компонентах | API-клиент + composables + Pinia | 6 |
| 11 | Типы ответов API пишутся руками | Типы генерируются из OpenAPI (Scramble) | 6 |
| 12 | Самописная валидация форм | VeeValidate + Zod, ошибки 422 с бэкенда в полях | 6 |
| 13 | Scout, драйвер `database` (FULLTEXT MariaDB) | Scout + Meilisearch, индексация через очередь | 7 |
| 14 | Кеш без инвалидации (`remember` на 60 с) | Продуманная инвалидация, теги, `Cache::flexible`, locks | 7 |
| 15 | Larastan уровень 5 | Larastan уровень 8, без baseline | 3 → 7 |
| 16 | Laravel Events внутри процесса | Transactional Outbox + RabbitMQ | 8 |
| 17 | Dev-образ Docker | Multi-stage prod-образ, не от root, CD | 9 |

> **Исключение из правила «просто → коммерчески»: тесты с первого дня идут на MariaDB, не на SQLite.**
> SQLite ведёт себя иначе именно там, где это важно для проекта: `lockForUpdate` фактически ничего не блокирует,
> `whereFullText` не поддерживается, JSON и строгость типов отличаются. Тесты были бы зелёными на SQLite
> и красными на MariaDB, а время ушло бы на отладку разницы движков, а не на изучение Laravel.

---

## 3. Учебный проект: LoadHub (мини-TMS)

### 3.1. Роли
- **Администратор** — пользователи, роли, справочники (типы трейлеров, брокеры).
- **Диспетчер** — создаёт грузы, назначает водителей, ведёт чат по грузу, видит карту.
- **Водитель** — видит свои грузы, меняет статус (picked up, delivered), загружает документы, передаёт координаты.
- **Брокер (внешний)** — видит груз по публичной tracking-ссылке без логина. Для партнёров есть API по токену.

### 3.2. Функции (только то, что нужно для изучения стека)
- Грузы: статусы `new → assigned → picked_up → in_transit → delivered → closed` (+ `cancelled`), точки pickup/delivery, ставка, вес.
- Назначение водителя с защитой от гонки: двух диспетчеров, назначающих одного водителя одновременно.
- Чат по грузу в реальном времени, индикатор «печатает», онлайн-статус диспетчеров.
- Трекинг: водитель шлёт координаты, диспетчер видит движение на карте в реальном времени.
- Документы (BOL, POD) с превью, генерация превью в очереди.
- Уведомления: в браузере, email, Telegram.
- Контроль опозданий: scheduler проверяет, что груз не забран вовремя, и эскалирует.
- Отчёт по грузам за период в Excel (в фоне).
- Публичная tracking-ссылка (signed URL).
- Партнёрский API v1 с токенами и вебхуками.

### 3.3. Технологический стек

**Бэкенд:** PHP 8.4, Laravel 13, MariaDB 11.4 LTS (драйвер `mariadb`), Redis 7, Horizon, Reverb, Sanctum, Scout (database → Meilisearch), spatie/laravel-permission, spatie/laravel-data, dedoc/scramble, Pest 5, Larastan, Pint, Rector.
Позже: RabbitMQ 4 (`php-amqplib`), MinIO, Sentry.

**Фронтенд:** Vue 3 (`<script setup>`), TypeScript, Vite, Vue Router, Pinia, Axios, Laravel Echo + pusher-js, VeeValidate + Zod, UI-кит (PrimeVue — много готовых таблиц и форм, похоже на привычные вам kartik-виджеты), Leaflet для карты, Vitest, Playwright, ESLint + Prettier.

> Перед установкой каждого пакета проверяйте в его composer.json/релизах поддержку Laravel 13.

### 3.4. Что сознательно не входит в план
Kubernetes, Octane, Filament, Traefik, Prometheus/Grafana, микрофронтенды. Это полезно, но на этом этапе отвлекает. Список для изучения после плана — в разделе 9.

---

## 4. MariaDB в Laravel: что нужно знать заранее

| Тема | Суть |
|---|---|
| Драйвер | `DB_CONNECTION=mariadb`. В Laravel это отдельный драйвер, не `mysql` |
| JSON | В MariaDB `JSON` — это `LONGTEXT` с `CHECK`. Для поиска по полю JSON делайте виртуальную (generated) колонку и индекс на неё |
| Частичных индексов нет | Замена: generated-колонка + индекс или составной индекс |
| Полнотекстовый поиск | `FULLTEXT`-индекс + `whereFullText()`. На нём строится первая итерация поиска (Scout database driver) |
| Транзакции | InnoDB, REPEATABLE READ по умолчанию, gap locks. Возможны дедлоки, поэтому `DB::transaction($fn, attempts: 3)` |
| Блокировки | `lockForUpdate()` = `SELECT ... FOR UPDATE`, `sharedLock()` = `LOCK IN SHARE MODE` |
| Анализ запросов | `EXPLAIN`, `ANALYZE FORMAT=JSON`, slow query log |
| Схема | `php artisan schema:dump` работает. Пригодится, когда миграций становится много (как 1200 в gLogic) |
| Кодировка | Только `utf8mb4` / `utf8mb4_unicode_ci` |

---

## 5. Docker: минимум на старте

### 5.1. Структура репозитория

```
loadhub/
├── Makefile
├── docker-compose.yml
├── docker/
│   ├── php/Dockerfile        # base → dev (prod-стадия появится на этапе 9)
│   ├── php/php.ini
│   ├── nginx/default.conf
│   └── mariadb/init.sql      # тестовая БД + GRANT
├── backend/                  # Laravel 13
├── frontend/                 # Vue 3 + TS
└── docs/
    ├── adr/
    ├── refactoring-debt.md   # реестр из раздела 2.1
    └── yii2-vs-laravel.md
```

### 5.2. Сервисы по этапам

| Этап | Добавляем |
|---|---|
| 0 | `nginx`, `php` (fpm), `mariadb`, `redis`, `mailpit`, `frontend` (Vite) |
| 4 | `horizon`, `scheduler`, `minio` |
| 5 | `reverb` |
| 7 | `meilisearch` |
| 8 | `rabbitmq`, `consumer` (`events:consume`), `outbox-publisher` (`outbox:publish`); сервис `notifications` — свой php-fpm для внутреннего API, свой consumer и воркер очереди |

Новые сервисы, которые нужны не всегда, подключайте через `profiles` в compose.

### 5.3. docker-compose.yml для этапа 0

```yaml
x-php: &php
  build: { context: ., dockerfile: docker/php/Dockerfile, target: dev }
  # env_file здесь намеренно НЕТ — см. ловушку 4 ниже
  volumes: ["./backend:/var/www/html"]
  depends_on:
    mariadb: { condition: service_healthy }
    redis:   { condition: service_healthy }

services:
  nginx:
    image: nginx:1.27-alpine
    ports: ["80:80"]
    volumes:
      - ./backend:/var/www/html:ro
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on: [php]

  php:
    <<: *php

  frontend:
    image: node:24.21-alpine   # npm 10 из node:22 падает на зависимостях create-vue
    working_dir: /app
    command: sh -c "if [ -f package-lock.json ]; then npm ci; else npm install; fi && npm run dev -- --host 0.0.0.0"
    volumes: ["./frontend:/app"]
    ports: ["5173:5173"]

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
    ports: ["3307:3306"]   # 3306 на хосте часто занят локальной MariaDB
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 5s
      retries: 20

  redis:
    image: redis:7.4-alpine
    healthcheck: { test: ["CMD", "redis-cli", "ping"], interval: 5s, retries: 10 }

  mailpit:
    image: axllent/mailpit:v1.21
    ports: ["8025:8025"]

volumes:
  dbdata:
```

#### Ловушки, которые стоит знать заранее

**1. Тестовая база и права.** `MARIADB_USER` получает права только на базу из `MARIADB_DATABASE`. Без явного `GRANT` тесты упадут с «Access denied». `docker/mariadb/init.sql`:

```sql
CREATE DATABASE IF NOT EXISTS loadhub_testing
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- шаблон с % — для `php artisan test --parallel` (Laravel создаёт loadhub_testing_test_1, _2, ...)
GRANT ALL PRIVILEGES ON `loadhub\_testing%`.* TO 'loadhub'@'%';
FLUSH PRIVILEGES;
```

Init-скрипты выполняются **только при первом создании volume**. Если база уже была поднята без скрипта, нужно `docker compose down -v` (данные удалятся) или выполнить SQL вручную под root.

**2. Первый запуск фронта.** `npm ci` падает без `package-lock.json`, поэтому в compose стоит проверка с откатом на `npm install`. А пока в `frontend/` нет даже `package.json`, контейнер не стартует вообще. Поэтому проект Vue создаётся один раз до `make init`:

```bash
docker compose run --rm --no-deps frontend npm create vue@latest .
```

**3. Имя PHP-сервиса в nginx.** Сервис называется `php`, значит в `fastcgi_pass` стоит `php:9000` (в первом плане был `core`, при копировании конфигов это легко пропустить). `docker/nginx/default.conf`:

```nginx
server {
    listen 80;
    root /var/www/html/public;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass php:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```

**4. Тесты могут стереть рабочую базу.** Если передать `backend/.env` в контейнер через `env_file`, то `DB_DATABASE=loadhub` станет настоящей переменной окружения процесса. `<env>` в `phpunit.xml` по умолчанию **не перезаписывает** уже заданные переменные, и `RefreshDatabase` очистит рабочую базу `loadhub` вместо `loadhub_testing`. Поэтому:
- в compose нет `env_file`: Laravel сам читает `.env` из смонтированной папки;
- в `phpunit.xml` на всякий случай стоит `force="true"`:

```xml
<env name="APP_ENV" value="testing" force="true"/>
<env name="DB_CONNECTION" value="mariadb" force="true"/>
<env name="DB_DATABASE" value="loadhub_testing" force="true"/>
```

**5. Хосты в `backend/.env`** — имена сервисов compose, а не `127.0.0.1`: `DB_HOST=mariadb`, `REDIS_HOST=redis`, `MAIL_HOST=mailpit`, `MAIL_PORT=1025`.

### 5.4. Dockerfile для этапа 0

```dockerfile
FROM php:8.4-fpm-alpine AS base
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions pdo_mysql redis pcntl intl zip gd bcmath opcache exif
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/html

FROM base AS dev
RUN install-php-extensions xdebug
COPY docker/php/php.ini /usr/local/etc/php/conf.d/99-app.ini
ARG UID=1000
ARG GID=1000
RUN addgroup -g ${GID} app && adduser -D -u ${UID} -G app app
USER app
```

> `pdo_mysql` обслуживает и MariaDB. Отдельного расширения не нужно.

---

## 6. План по неделям

```
Неделя: 1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20
Этап 0  █
Этап 1     █  █
Этап 2           █  █
Этап 3                 █  █
Этап 4                       █  █
Этап 5                             █  █
Этап 6                                   █  █
Этап 7                                         █  █
Этап 8                                               █  █  █
Этап 9                                                        █  █
        └──────────── ядро (1–15) ─────────────────┘ └─ расширение ─┘
```

Каждую неделю выделяйте последний день на **ретро**: обновить `yii2-vs-laravel.md`, закрыть пункты реестра, записать ADR, если принималось решение.

---

### Этап 0. Окружение и скелет (неделя 1)

**Изучаем:**
- Установка Laravel 13 в контейнере, структура «тонкого» скелета: `bootstrap/app.php` (роуты, middleware, исключения), `routes/`, `config/`, `.env`
- `php artisan install:api` (Sanctum + `routes/api.php`)
- Жизненный цикл запроса: `public/index.php` → Kernel → middleware → роутер → контроллер → ответ
- `npm create vue@latest` с TypeScript, Router, Pinia, Vitest, ESLint, Prettier

**Делаем:**
- compose из раздела 5.3, `Makefile` (`init`, `up`, `down`, `sh`, `test`, `lint`, `fresh`)
- Pint, Larastan (уровень 5), Pest
- Тестовая БД: в `phpunit.xml` задать `DB_CONNECTION=mariadb`, `DB_DATABASE=loadhub_testing` с `force="true"` (ловушка 4 в разделе 5.3); в тестах трейт `RefreshDatabase`
- Простой GitHub Actions: Pint → Larastan → Pest, с сервисом `mariadb:11.4` для тестов
- ADR-0001: «Почему MariaDB, свой Docker и отдельное SPA»

**Готово, когда:**
- [ ] `git clone && make init` поднимает всё на чистой машине
- [ ] Laravel на `localhost`, Vue на `:5173`, Mailpit на `:8025`
- [ ] CI зелёный, тесты и локально, и в CI идут на MariaDB
- [ ] После `make test` данные в рабочей базе `loadhub` на месте (проверено)

---

### Этап 1. Фундамент Laravel (недели 2–3)

**Изучаем (именно в таком порядке):**
1. **Сервис-контейнер и Service Providers.** `bind`, `singleton`, `scoped`, контекстные биндинги, автовайринг. Фасады и как они устроены (`getFacadeAccessor`). Это самая важная тема: прочитайте код `Illuminate\Container\Container::build()`.
2. Роутинг, группы, route model binding, middleware
3. Eloquent: связи (все типы), scopes, casts (в том числе enum), accessors/mutators, soft deletes, `$fillable` против `$guarded`
4. Миграции, фабрики, сидеры
5. Form Requests, API Resources
6. Sanctum SPA-аутентификация (cookie + CSRF) и почему не токен в localStorage
7. Обработка исключений в `bootstrap/app.php`: единый JSON-формат ошибок

**Итерация A:** CRUD грузов в стандартной структуре Laravel (`app/Models`, `app/Http/Controllers`). Роль — колонка в `users`, валидация в контроллере.

**Итерация B (к концу недели 3):** реестр п. 1 и 2. Form Requests, API Resources, единый формат ошибок (422/403/404/500).

**Делаем:**
- Модели: `User`, `Load`, `LoadStop` (pickup/delivery), `Driver`, `Broker`, `TrailerType`
- API: логин, логаут, `me`; CRUD грузов; список с фильтрами (статус, дата, водитель) и пагинацией
- Сидеры: 30 водителей, 10 диспетчеров, 2 000 грузов
- Feature-тесты Pest на каждый эндпоинт

**Готово, когда:**
- [ ] Можете без подсказок объяснить путь запроса и как контейнер резолвит зависимость
- [ ] Все эндпоинты покрыты тестами (позитив, валидация, 401/403)

---

### Этап 2. Vue 3 + TypeScript: основы (недели 4–5)

Новые функции бэкенда на эти две недели не добавляются, весь фокус на фронт. Исключение — настройки, без которых SPA не заработает (Sanctum, сессии, CORS, см. ниже).

**Изучаем:**
- TypeScript: типы, интерфейсы, union, generics, `Partial`/`Pick`/`Record`, type narrowing
- Vue: реактивность (`ref`, `reactive`, `computed`, `watch`), props/emits с типами, slots, `v-model` на компонентах, `defineModel`, жизненный цикл
- Composables: свои `useXxx()`
- Vue Router: вложенные маршруты, guards, lazy loading
- Pinia: setup-stores
- Официальный туториал vuejs.org — целиком, это 1–2 дня

**Итерация A:** страницы входа, списка грузов, карточки и создания груза. Axios вызывается прямо в компонентах, типы пишутся руками.

**Делаем:**
- Настройка Sanctum для SPA: `SANCTUM_STATEFUL_DOMAINS`, `SESSION_DOMAIN`, CORS с `supports_credentials`, запрос `/sanctum/csrf-cookie` перед логином. Разберитесь в этом варианте, а затем попробуйте `server.proxy` в Vite (`/api`, `/sanctum` → nginx): фронт и API становятся одним origin, и CORS в dev не нужен. Именно так фронт будет раздаваться в проде через nginx
- Guard в роутере: неавторизованного пользователя отправляет на `/login`
- Раскладка приложения на PrimeVue: меню, таблица грузов с фильтрами и пагинацией из API

**Готово, когда:**
- [ ] Диспетчер входит, видит грузы, создаёт груз, ошибки 422 показываются в форме
- [ ] Обновление страницы (F5) не выкидывает из сессии

---

### Этап 3. Переделка под коммерческий уровень (недели 6–7)

Ключевой этап: превращаем учебный код в production-код. Здесь станет понятно, зачем нужен каждый слой.

**Изучаем:**
- Action-классы, DTO (spatie/laravel-data), где проходит граница между Action и моделью
- Enum + машина состояний: метод `canTransitionTo()`, запрет недопустимых переходов
- Транзакции, `lockForUpdate`, дедлоки и `attempts`, оптимистичная блокировка через колонку `version`
- N+1: `Model::preventLazyLoading()`, `with`, `withCount`, подзапросы; индексы, `EXPLAIN` в MariaDB
- Events, Listeners, Observers: когда что использовать
- spatie/laravel-permission + Policies
- Модульная структура и архитектурные тесты Pest (`arch()`)
- Фейки в тестах: `Event::fake`, `Queue::fake`, `Mail::fake`, `Notification::fake`

**Итерация B (реестр п. 3, 4, 5, 6):**

```
app/
├── Modules/
│   ├── Identity/      # пользователи, роли, auth
│   ├── Fleet/         # водители, трейлеры
│   ├── Loads/         # грузы, стопы, статусы, назначения
│   ├── Documents/     # появится на этапе 4
│   ├── Notifications/ # появится на этапе 4
│   └── Messaging/     # появится на этапе 5
└── Shared/            # базовые классы, value objects
```
В каждом модуле: `Actions/`, `Data/`, `Enums/`, `Events/`, `Http/{Controllers,Requests,Resources}`, `Models/`, `Policies/`, `Providers/`, `Database/`, `routes.php`.

Правила:
1. Модуль не обращается к моделям другого модуля напрямую, только через `Contracts/`.
2. Между модулями хранятся ID, а не Eloquent-связи.
3. Контроллер: Request → Action → Resource.

**Делаем:**
- Actions: `CreateLoad`, `AssignDriver` (с блокировкой и тестом на конкурентное назначение), `ChangeLoadStatus`, `CancelLoad`
- История статусов через события
- Larastan до уровня 6
- ADR-0002: «Модульный монолит и правила границ»

**Готово, когда:**
- [ ] Все пункты реестра, отнесённые к этапам 1 и 3, закрыты (п. 15 — частично: Larastan уровень 6, уровень 8 на этапе 7)
- [ ] Список грузов работает за фиксированное число SQL-запросов (есть тест)
- [ ] `arch()`-тесты падают, если модуль импортирует модель чужого модуля
- [ ] Нельзя перевести груз из `new` сразу в `delivered` (есть тест)

---

### Этап 4. Очереди, фон, уведомления, файлы (недели 8–9)

**Изучаем:**
- Jobs: `tries`, `backoff`, `timeout`, `failed()`, `ShouldBeUnique`, job middleware (`WithoutOverlapping`, `RateLimited`)
- `Bus::chain`, `Bus::batch`
- Идемпотентность: задача может выполниться дважды
- `afterCommit`: почему задачу нельзя отправлять до коммита транзакции
- Horizon: супервизоры, приоритетные очереди, метрики
- Scheduler: `withoutOverlapping`, `onOneServer`
- Notifications: `mail`, `database`, свой канал Telegram
- Storage: локально, затем S3/MinIO, `temporaryUrl`

**Итерация A:** очередь `database`, уведомления синхронно, файлы на локальном диске.
**Итерация B (реестр п. 7, 8, 9):** Redis + Horizon, очереди `high` / `default` / `low`, все уведомления через очередь, файлы в MinIO.

**Делаем:**
- Модуль **Documents**: загрузка BOL/POD, превью через очередь
- Модуль **Notifications**: назначение на груз, смена статуса, новое сообщение; настройки подписок пользователя
- Контроль опозданий: scheduler раз в минуту проверяет грузы, не забранные вовремя, и эскалирует
- Экспорт грузов за период в Excel через batch, уведомление «отчёт готов» со ссылкой
- Команда `php artisan loads:generate {count}` для больших объёмов: вставка пачками по 1 000 строк через `insert()`, а не `Factory::create()` по одной, иначе 100 000 грузов будут генерироваться очень долго. Запускается вручную, в `DatabaseSeeder` не входит

**Готово, когда:**
- [ ] Экспорт 100 000 грузов (сгенерированных `loads:generate 100000`) не падает по памяти (`lazy()` / chunking)
- [ ] Упавшие задачи видны в Horizon и перезапускаются
- [ ] Повторный запуск задачи уведомления не отправляет письмо дважды (есть тест)

---

### Этап 5. Реальное время: Reverb (недели 10–11)

**Изучаем:**
- `ShouldBroadcast`, `ShouldBroadcastNow`, каналы public / private / presence, `routes/channels.php`
- Reverb: запуск, проксирование через nginx, масштабирование через Redis
- Laravel Echo: подписки, переподключение, whisper
- Отличия от вашего Workerman: протокол Pusher, авторизация каналов через HTTP

**Делаем:**
- Чат по грузу (модуль **Messaging**): сообщения, «печатает…», прочитано/не прочитано
- Presence-канал: кто из диспетчеров онлайн
- Трекинг: водитель шлёт координаты (для учёбы — эмулятор на фронте), диспетчер видит движение маркера на карте Leaflet. Координаты пишутся в БД пачками через очередь, а не каждым запросом
- Живое обновление таблицы грузов у диспетчеров
- Колокольчик уведомлений в реальном времени. Сразу оформите его как контракт, а не как деталь Laravel: канал `users.{id}` (`PrivateChannel`, на уровне протокола — `private-users.{id}`), имя события через `broadcastAs()` (например, `notification.created`), фиксированная структура payload. Опишите контракт в `docs/contracts/realtime.md`. На этапе 8 уведомления начнёт отправлять другое приложение, и фронт не должен этого заметить

**Готово, когда:**
- [ ] Два браузера переписываются в реальном времени
- [ ] Подписка на чужой приватный канал запрещена (есть тест)
- [ ] После перезапуска контейнера `reverb` фронт переподключается сам

---

### Этап 6. Фронтенд коммерческого уровня (недели 12–13)

**Итерация B для фронта (реестр п. 10, 11, 12):**
- Структура по фичам: `src/features/loads/{api,components,composables,stores,types}`
- API-клиент: единый axios-инстанс, интерсепторы 401 (выход) и 419 (обновить CSRF), нормализация ошибок
- Типы генерируются из OpenAPI (Scramble отдаёт спецификацию, `openapi-typescript` генерирует типы). Никаких `any`
- Формы: VeeValidate + Zod, ошибки 422 с бэкенда попадают в поля
- Права на фронте: директива или компонент `can('loads.assign')` на основе данных `me`
- Состояния загрузки, пустые состояния, обработка ошибок на каждом экране

**Тесты:**
- Vitest + Vue Test Utils: composables и ключевые компоненты
- Playwright: 3–4 E2E-сценария (вход; создание груза → назначение → у водителя появилось уведомление в колокольчике → чат; водитель: picked up → delivered → загрузка POD)
- ESLint + Prettier + `vue-tsc --noEmit` + тесты в CI

**Готово, когда:**
- [ ] Полный сценарий «диспетчер создал → назначил → водитель забрал → доставил → документы загружены» проходит в E2E
- [ ] `vue-tsc` без ошибок, `any` отсутствует или обоснован комментарием
- [ ] Изменение контракта API ломает сборку фронта (благодаря генерации типов)

---

### Этап 7. Кеш, поиск, безопасность, публичный API (недели 14–15)

**Изучаем:**
- Кеш: `remember`, `flexible`, теги (Redis), `Cache::lock`, стратегии инвалидации
- Сессии и кеш в разных базах Redis
- Scout: драйвер `database` (FULLTEXT MariaDB), затем Meilisearch
- OWASP для Laravel: mass assignment, IDOR, XSS, CSRF, SQL-инъекции через `raw`
- Sanctum API-токены с abilities, rate limiting по токену, версионирование `/api/v1`
- Вебхуки: подпись HMAC, повторы, idempotency key
- Структурированные JSON-логи, request id через `Context` (он автоматически попадает в задачи очередей)

**Итерация B (реестр п. 13, 14, 15):** Meilisearch, продуманная инвалидация кеша, Larastan 8.

**Делаем:**
- Дашборд диспетчера: грузы по статусам, опоздания, загрузка водителей (агрегаты в SQL + кеш)
- Поиск по грузам (номер, адрес, брокер) и сообщениям чата
- Публичная tracking-ссылка (signed URL с истечением)
- Партнёрский API v1: токены со скоупами, исходящие вебхуки о смене статуса груза
- Нагрузочный тест k6 для списка и поиска, результаты до и после оптимизаций в `docs/`

**Готово, когда:**
- [ ] IDOR-тесты на все ключевые эндпоинты
- [ ] Дашборд берётся из кеша и корректно обновляется при изменениях
- [ ] По request id в логах видна вся цепочка, включая задачи очереди
- [ ] **Весь реестр до п. 15 включительно закрыт → ядро плана пройдено**

---

## 7. Расширение (недели 16–20)

### Этап 8. RabbitMQ и первый микросервис (недели 16–18)

Ваш опыт RabbitMQ из Yii2 здесь ускорит работу. Новое — это паттерны надёжности и то, как это встраивается в Laravel.

**Изучаем:**
- Transactional Outbox: событие пишется в таблицу `outbox_messages` в той же транзакции, отдельный процесс публикует его
- Идемпотентный консьюмер: таблица обработанных `message_id`
- Topic exchange, routing keys (`loads.load.status_changed.v1`), DLX, отложенные повторы
- Контракты событий и их версионирование
- Database per service
- Межсервисная аутентификация (сервисный токен)

**Делаем (реестр п. 16):**
- `app/Shared/EventBus`: интерфейс `EventPublisher`, реализация на `php-amqplib`, команда `events:consume` (контейнер `consumer`)
- Outbox-публикатор — команда `outbox:publish` в отдельном контейнере `outbox-publisher` (из того же образа). Это долгоживущий цикл: выбрать неопубликованные записи (`SELECT ... FOR UPDATE SKIP LOCKED` — поддерживается в MariaDB с 10.6), опубликовать с publisher confirms, пометить отправленными, короткая пауза. Scheduler раз в минуту не подходит: уведомления и чат задерживались бы до минуты. `SKIP LOCKED` позволяет безопасно запустить несколько реплик публикатора, но тогда порядок событий между репликами не гарантирован: консьюмеры должны быть идемпотентными и не полагаться на порядок (или сравнивать версию сущности). Для учёбы достаточно одной реплики
- Выносим **Notifications** в отдельное Laravel-приложение `services/notifications`. Монолит только публикует события
- **Своя база в той же MariaDB — с отдельным пользователем.** Создайте базу `notifications` и пользователя `notifications` с `GRANT ALL ON notifications.*` и без прав на `loadhub`. Монолиту — такой же пользователь без прав на `notifications`. Тогда нарушение принципа database per service (случайный JOIN или запрос в чужую базу) сразу даст ошибку доступа, а не пройдёт незаметно
- **Кто отправляет уведомления в Reverb после выноса.** Колокольчик с этапа 5 работает через broadcasting монолита, и без явного решения вынос его сломает. Варианты:

  | | A. Сервис публикует в Reverb сам (**выбираем**) | B. Сервис возвращает событие в монолит, тот транслирует |
  |---|---|---|
  | Как | В сервисе драйвер broadcasting `reverb` с теми же `REVERB_APP_ID/KEY/SECRET`, тот же канал и имя события из `docs/contracts/realtime.md` | Сервис публикует в RabbitMQ `notifications.notification.created.v1`, консьюмер монолита делает broadcast |
  | Плюсы | Меньше звеньев и задержка; функция целиком принадлежит сервису | Секрет Reverb только в монолите; сервис не знает о WebSocket |
  | Минусы | Секрет Reverb есть у двух приложений; формат каналов — общий контракт, менять его нужно синхронно | Лишний переход через брокер; уведомления зависят от доступности монолита |

  Авторизация приватных каналов при любом варианте остаётся в монолите (`routes/channels.php`), потому что сессии пользователей там. Reverb проверяет подпись, а не то, какое приложение опубликовало событие. Решение запишите в ADR-0004 **до** начала выноса
- **HTTP-API уведомлений после выноса.** Фронт читает историю колокольчика и меняет настройки подписок через API монолита, а данные теперь лежат в сервисе. Чтобы фронт не менялся и аутентификация оставалась в одном месте, монолит работает как BFF: эндпоинты `/api/notifications/*` остаются в монолите, проверяют сессию и права и проксируют запрос в сервис по внутренней сети с сервисным токеном и `X-User-Id`. Сервис наружу не открыт. Запишите это в тот же ADR-0004
- DLQ + команда повторной обработки

**Готово, когда:**
- [ ] Сервис уведомлений остановлен на 10 минут → после запуска всё доставлено, ничего не потеряно
- [ ] Колокольчик работает после выноса без изменений на фронте: E2E-тест из этапа 6 проходит, а в монолите нет кода отправки уведомлений
- [ ] Пользователь `notifications` не может прочитать таблицы монолита (проверено), монолит — таблицы сервиса
- [ ] Повторная доставка сообщения не создаёт дубль (есть тест)
- [ ] ADR-0003 «Почему Outbox» + Mermaid-схема взаимодействия сервисов

### Этап 9. Продакшен (недели 19–20)

**Делаем (реестр п. 17):**
- Prod-стадия Dockerfile: `composer install --no-dev`, `--classmap-authoritative`, `php artisan optimize`, запуск не от root, без xdebug; сборка фронта в статику (nginx)
- `docker-compose.prod.yml`, CD: сборка образов → GHCR → деплой на VPS
- Zero-downtime: миграции «расширить → перенести → сузить», `horizon:terminate`, graceful-перезапуск Reverb
- HTTPS, Sentry (бэк + фронт), health-check эндпоинты
- Бэкап MariaDB (`mariadb-dump` / `mariabackup`) по расписанию + проверенное восстановление

**Готово, когда:**
- [ ] Проект доступен по домену с HTTPS, деплой автоматический
- [ ] База хотя бы раз восстановлена из бэкапа
- [ ] Ошибка в любом сервисе видна в Sentry с request id

---

## 8. Стандарты кода (Definition of Done для каждой задачи)

Бэкенд-пункты применяются ко всему коду с этапа 3, фронтенд-пункты — с этапа 6.

**Бэкенд:**
- [ ] `declare(strict_types=1)`, типы у всех параметров и возвращаемых значений
- [ ] Тонкий контроллер, логика в Action, вход — Form Request/DTO, выход — Resource
- [ ] Права проверены через Policy, есть тест на 403
- [ ] Нет N+1 (`preventLazyLoading` включён в dev и тестах)
- [ ] Операции, меняющие несколько таблиц, выполняются в транзакции; задачи и события отправляются `afterCommit`
- [ ] Миграция обратима и не блокирует большую таблицу надолго
- [ ] Pint, Larastan, Pest — зелёные

**Фронтенд:**
- [ ] Типы из OpenAPI, нет `any`
- [ ] Запросы к API только через `features/*/api`, не из шаблона компонента
- [ ] Обработаны состояния loading / empty / error
- [ ] ESLint, `vue-tsc`, Vitest — зелёные

**Процесс:**
- Ветка на задачу → PR → CI → self-review по этому чек-листу → merge
- Conventional Commits: `feat(loads): add driver assignment lock`

---

## 9. Шпаргалка Yii2 → Laravel

| Yii2 | Laravel |
|---|---|
| `Yii::$app->component` | Контейнер, DI через конструктор, фасады |
| `components` в конфиге | Service Providers (`register` / `boot`) |
| ActiveRecord | Eloquent |
| `rules()` модели | Form Request |
| `behaviors()` | Трейты, Observers, события модели |
| AccessControl / VerbFilter | Middleware, Policies |
| `authManager` RBAC | Gates, Policies, spatie/laravel-permission |
| `yii migrate` | `php artisan migrate`, `schema:dump` |
| Gii | `php artisan make:*` |
| GridView / kartik | PrimeVue DataTable + API-пагинация |
| yii2-queue | Queues + Horizon |
| `Yii::$app->cache` | `Cache`, теги, `flexible`, `lock` |
| Workerman-сокеты | Reverb + Broadcasting + Echo |
| Codeception | Pest |
| Модули Yii2 | Нет из коробки — `app/Modules` + свои провайдеры |

**После плана (по желанию):** Octane (FrankenPHP), Filament для админок, Inertia (сравнить с SPA), Kubernetes, OpenTelemetry.

---

## 10. Контрольные вопросы

1. Как контейнер резолвит зависимость? `bind` / `singleton` / `scoped` — в чём разница, особенно для очередей и Octane?
2. Путь запроса от `public/index.php` до ответа.
3. Почему задачу нужно отправлять после коммита транзакции? Что будет иначе?
4. Как защититься от гонки при назначении водителя? Пессимистичная или оптимистичная блокировка — что выбрать и когда?
5. Что будет с задачами в очереди при деплое новой версии?
6. Как работает Sanctum SPA-аутентификация и какие настройки ломают её при разных доменах?
7. Как масштабировать Reverb на несколько серверов?
8. Как найти N+1 и почему `preventLazyLoading` не включают в проде?
9. JSON в MariaDB и в PostgreSQL: как индексировать поиск по JSON-полю?
10. Зачем Transactional Outbox? Что будет без него при недоступном брокере?
11. Как переименовать колонку в большой таблице без простоя?
12. Как устроена инвалидация кеша дашборда и где её слабые места?
13. Когда модульный монолит лучше микросервисов?

---

## 11. Ресурсы

- laravel.com/docs — прочитать разделы Architecture Concepts, The Basics, Database, Eloquent, Digging Deeper целиком; при апгрейде — Upgrade Guide и Release Notes 13.x
- Laracasts — Laravel, Pest, Vue, TypeScript
- «Laravel Beyond CRUD» (Spatie) — к этапу 3
- vuejs.org, pinia.vuejs.org, router.vuejs.org, TypeScript Handbook
- mariadb.com/kb — индексы, JSON, блокировки InnoDB
- microservices.io (Outbox, Idempotent Consumer), RabbitMQ Reliability Guide — к этапу 8
- Исходники: `vendor/laravel/framework` — читать, когда что-то непонятно

> Не подгоняйте себя под недели. Критерий прохождения этапа — чек-боксы «Готово, когда» и закрытые пункты реестра, а не календарь.
