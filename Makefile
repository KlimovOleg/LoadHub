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
