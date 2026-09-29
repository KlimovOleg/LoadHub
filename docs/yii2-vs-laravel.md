# Yii2 → Laravel: личный конспект

Правило: на каждую новую концепцию — короткая запись «как было в Yii2 → как в Laravel → в чём подвох».
Пополнять в день ретро в конце каждой недели.

## Шпаргалка

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

## Записи

### Конфигурация окружения

- **Yii2:** `environments/` + `php init` копирует конфиги под окружение, `main-local.php`.
- **Laravel:** один `.env` на окружение, `config/*.php` читают его через `env()`.
- **Подвох:** `env()` вызывать только внутри `config/*.php` — после `config:cache` он возвращает `null`
  в остальном коде. Реальные переменные окружения процесса важнее `.env` (из-за этого `phpunit.xml`
  использует `force="true"`).
