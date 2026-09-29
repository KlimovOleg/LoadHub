# ---------- base ----------
FROM php:8.4-fpm-alpine AS base

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions pdo_mysql redis pcntl intl zip gd bcmath opcache exif

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# ---------- dev ----------
FROM base AS dev

RUN install-php-extensions xdebug
COPY docker/php/php.ini /usr/local/etc/php/conf.d/99-app.ini

# Пользователь с UID/GID хоста, чтобы файлы в volume не принадлежали root.
# На macOS GID 20 (staff) уже занят в Alpine группой dialout — тогда используем её.
ARG UID=1000
ARG GID=1000
RUN if ! getent group "${GID}" >/dev/null; then addgroup -g "${GID}" app; fi \
 && adduser -D -u "${UID}" -G "$(getent group "${GID}" | cut -d: -f1)" app

USER app

# prod-стадия появится на этапе 9
