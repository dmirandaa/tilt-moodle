# =============================================================================
# Moodle — PHP + Apache2 image
# =============================================================================
# Build arguments:
#   PHP_VERSION    (default: 7.4) — 7.4 | 8.0 | 8.1 | 8.2 | 8.3 | 8.4
#   MOODLE_BRANCH  (default: MOODLE_403_STABLE)
#                — MOODLE_401_STABLE   for PHP 7.4
#                — MOODLE_403_STABLE   for PHP 8.x  (recommended)
#
# Examples:
#   docker build --build-arg PHP_VERSION=8.2 --build-arg MOODLE_BRANCH=MOODLE_403_STABLE .
#   docker build --build-arg PHP_VERSION=7.4 --build-arg MOODLE_BRANCH=MOODLE_401_STABLE .
# =============================================================================

ARG PHP_VERSION=7.4
FROM php:${PHP_VERSION}-apache

ARG MOODLE_BRANCH=MOODLE_38_STABLE
# Store MOODLE_BRANCH as environment variable so entrypoint can use it at runtime
ENV MOODLE_BRANCH=${MOODLE_BRANCH}

LABEL org.opencontainers.image.description="Moodle LMS on PHP ${PHP_VERSION} + Apache2"

# ── System packages ───────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    cron \
    git \
    libcurl4-openssl-dev \
    libfreetype6-dev \
    libicu-dev \
    libjpeg-dev \
    libldap2-dev \
    libonig-dev \
    libpng-dev \
    libpq-dev \
    libssl-dev \
    libxml2-dev \
    libzip-dev \
    netcat-openbsd \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/*

# ── PHP extensions ────────────────────────────────────────────────────────────
# PHP 7.4+ (and all PHP 8.x) use the unified GD bundled build flags.
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg

# mbstring is bundled from PHP 8.0; install it only for PHP 7.x
# xmlrpc is bundled in PHP 7.x; not required by Moodle 4.x+ (dropped for PHP 8.x)
RUN PHP_MAJOR=$(php -r 'echo PHP_MAJOR_VERSION;') && \
    EXTRA_EXTS="" && \
    if [ "$PHP_MAJOR" = "7" ]; then EXTRA_EXTS="mbstring xmlrpc"; fi && \
    docker-php-ext-install -j"$(nproc)" \
    exif \
    gd \
    intl \
    ldap \
    mysqli \
    opcache \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    soap \
    zip \
    $EXTRA_EXTS

# ── phpredis (session and cache backend for Redis) ───────────────────────────
# 6.1.0 is the first stable line with PHP 8.4 fixes while still supporting PHP 7.4.
ARG PHPREDIS_VERSION=redis-6.1.0
RUN pecl install ${PHPREDIS_VERSION} \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/pear

# ── Apache ────────────────────────────────────────────────────────────────────
RUN a2enmod rewrite headers ssl socache_shmcb

# Generate a self-signed certificate for HTTPS
RUN openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/ssl/private/moodle-selfsigned.key \
    -out /etc/ssl/certs/moodle-selfsigned.crt \
    -subj "/C=BR/ST=SP/L=Sao_Paulo/O=Moodle/CN=localhost"

COPY moodle/apache-moodle.conf /etc/apache2/sites-available/000-default.conf

# ── PHP configuration tuned for Moodle ───────────────────────────────────────
RUN { \
    printf 'upload_max_filesize = 2G\n'; \
    printf 'post_max_size = 2G\n'; \
    printf 'memory_limit = 4G\n'; \
    printf 'max_execution_time = 600\n'; \
    printf 'max_input_vars = 5000\n'; \
    printf 'cgi.fix_pathinfo = 0\n'; \
    printf 'date.timezone = America/Sao_Paulo\n'; \
    } > /usr/local/etc/php/conf.d/moodle.ini

# ── Moodle source directory ──────────────────────────────────────────────────
# Bake the Moodle source into the image so all reads (notably the CLI installer)
# hit the container's local overlay filesystem rather than a slow host mount.
# MOODLE_SRC is the path (relative to the build context = repo root) of a
# locally-cloned Moodle checkout; Tilt live_update syncs edits on top at runtime.
# The entrypoint's git-clone step is skipped because config-dist.php is present.
ARG MOODLE_SRC=moodlefiles/moodle38
COPY ${MOODLE_SRC}/ /var/www/html/
RUN rm -f /var/www/html/config.php \
    && chown -R www-data:www-data /var/www/html \
    && find /var/www/html -type d -exec chmod 755 {} + \
    && find /var/www/html -type f -exec chmod 644 {} +

# ── Runtime directories ───────────────────────────────────────────────────────
# moodledata  — user uploads, temp files, session cache (persistent volume)
# moodle_config — stores config.php so it survives container rebuilds
RUN mkdir -p /var/www/moodledata /var/www/moodle_config \
    && chown -R www-data:www-data /var/www/moodledata /var/www/moodle_config \
    && chmod 770 /var/www/moodledata /var/www/moodle_config

VOLUME ["/var/www/moodledata", "/var/www/moodle_config"]

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY moodle/entrypoint.sh /usr/local/bin/entrypoint.sh
# Strip Windows CR characters so the script runs correctly on Linux
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["entrypoint.sh"]
CMD ["apache2-foreground"]
