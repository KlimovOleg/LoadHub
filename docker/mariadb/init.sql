-- Выполняется только при первом создании volume dbdata.
-- MARIADB_USER получает права только на MARIADB_DATABASE, поэтому GRANT на тестовую базу нужен явно.
CREATE DATABASE IF NOT EXISTS loadhub_testing
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Шаблон с % нужен для `php artisan test --parallel`: Laravel создаёт по базе на процесс
-- (loadhub_testing_test_1, loadhub_testing_test_2, ...). `\_` экранирует подчёркивание в шаблоне.
GRANT ALL PRIVILEGES ON `loadhub\_testing%`.* TO 'loadhub'@'%';
FLUSH PRIVILEGES;
