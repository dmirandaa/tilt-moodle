#!/bin/bash
# =============================================================================
# Moodle entrypoint
# =============================================================================
# Responsibilities:
#   1. Wait for the configured database to accept connections.
#   2. On the very first start, run the Moodle CLI installer.
#   3. Persist config.php to a dedicated volume so it survives container
#      rebuilds while the database volume remains intact.
#   4. Install a cron job for Moodle's task scheduler.
#   5. Hand off to Apache (apache2-foreground).
# =============================================================================
set -e

MOODLE_DIR=/var/www/html
MOODLE_DATA=/var/www/moodledata
MOODLE_CONFIG_DIR=/var/www/moodle_config
MOODLE_CONFIG="${MOODLE_CONFIG_DIR}/config.php"
MOODLE_CONFIG_LINK="${MOODLE_DIR}/config.php"

# ── Read env with fallbacks ───────────────────────────────────────────────────
DB_TYPE="${MOODLE_DB_TYPE:-mysqli}"
DB_HOST="${MOODLE_DB_HOST:-mysql}"
DB_PORT="${MOODLE_DB_PORT:-3306}"
DB_NAME="${MOODLE_DB_NAME:-moodle}"
DB_USER="${MOODLE_DB_USER:-moodle}"
DB_PASS="${MOODLE_DB_PASSWORD:-moodlepassword}"
DB_PREFIX="${MOODLE_DB_PREFIX:-mdl_}"
WWWROOT="${MOODLE_WWWROOT:-http://localhost:8080}"
ADMIN_USER="${MOODLE_ADMIN_USER:-admin}"
ADMIN_PASS="${MOODLE_ADMIN_PASSWORD:-P@ssw0rd}"
ADMIN_EMAIL="${MOODLE_ADMIN_EMAIL:-admin@example.com}"
SITE_NAME="${MOODLE_SITE_NAME:-Moodle LMS}"
SITE_SHORTNAME="${MOODLE_SITE_SHORTNAME:-moodle}"

# ── Wait for database ─────────────────────────────────────────────────────────
wait_for_db() {
    local host="$1"
    local port="$2"
    local max=60
    local i=0

    echo "[moodle] Waiting for database at ${host}:${port} ..."
    while ! nc -z "${host}" "${port}" 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -ge "$max" ]; then
            echo "[moodle] ERROR: timed out waiting for ${host}:${port}" >&2
            exit 1
        fi
        echo "[moodle] Not ready yet (${i}/${max}), retrying in 2 s ..."
        sleep 2
    done
    echo "[moodle] Database is up."
}

# Resolve host/port from DB_TYPE when the user hasn't overridden DB_HOST/DB_PORT
if [ "${DB_TYPE}" = "pgsql" ] && [ "${DB_HOST}" = "mysql" ]; then
    DB_HOST="postgres"
    DB_PORT="${MOODLE_DB_PORT:-5432}"
fi

wait_for_db "${DB_HOST}" "${DB_PORT}"

# Give the DB engine a couple of extra seconds to finish initialising
sleep 2

# ── Link or install config.php ────────────────────────────────────────────────
if [ -f "${MOODLE_CONFIG}" ]; then
    echo "[moodle] Existing config.php found — linking."
    ln -sf "${MOODLE_CONFIG}" "${MOODLE_CONFIG_LINK}"
else
    echo "[moodle] No config.php found — running Moodle CLI installer ..."
    echo "[moodle] This may take a few minutes on first boot."

    # Ensure correct ownership on writable directories
    chown -R www-data:www-data "${MOODLE_DATA}" "${MOODLE_CONFIG_DIR}"
    chmod 770 "${MOODLE_DATA}" "${MOODLE_CONFIG_DIR}"

    # Run the Moodle CLI installer
    php "${MOODLE_DIR}/admin/cli/install.php" \
        --wwwroot="${WWWROOT}" \
        --dataroot="${MOODLE_DATA}" \
        --dbtype="${DB_TYPE}" \
        --dbhost="${DB_HOST}" \
        --dbport="${DB_PORT}" \
        --dbname="${DB_NAME}" \
        --dbuser="${DB_USER}" \
        --dbpass="${DB_PASS}" \
        --prefix="${DB_PREFIX}" \
        --adminuser="${ADMIN_USER}" \
        --adminpass="${ADMIN_PASS}" \
        --adminemail="${ADMIN_EMAIL}" \
        --fullname="${SITE_NAME}" \
        --shortname="${SITE_SHORTNAME}" \
        --non-interactive \
        --agree-license

    # Fix ownership of generated config.php (created as root)
    chown www-data:www-data "${MOODLE_CONFIG_LINK}"

    # __DIR__ in the generated config.php resolves to the real file location,
    # not the symlink location. Replace it with the absolute Moodle path so
    # config.php works correctly when stored in the config volume and symlinked.
    sed -i "s|require_once(__DIR__ . '/lib/setup.php');|require_once('${MOODLE_DIR}/lib/setup.php');|" "${MOODLE_CONFIG_LINK}"

    # Persist config.php to the config volume and replace with symlink
    cp "${MOODLE_CONFIG_LINK}" "${MOODLE_CONFIG}"
    rm  "${MOODLE_CONFIG_LINK}"
    ln -sf "${MOODLE_CONFIG}" "${MOODLE_CONFIG_LINK}"

    echo "[moodle] Installation complete."
fi

# Ensure config.php in the volume is always readable by www-data,
# regardless of how/when it was created (cp runs as root, umask varies).
chown www-data:www-data "${MOODLE_CONFIG}"
chmod 640 "${MOODLE_CONFIG}"

# ── Moodle cron (task scheduler) ──────────────────────────────────────────────
if [ ! -f /etc/cron.d/moodle ]; then
    echo "*/1 * * * * www-data php ${MOODLE_DIR}/admin/cli/cron.php > /dev/null 2>&1" \
        > /etc/cron.d/moodle
    chmod 0644 /etc/cron.d/moodle
fi

# Start cron daemon (non-fatal — cron may already be running or unavailable)
service cron start 2>/dev/null || /usr/sbin/cron 2>/dev/null || true

# ── Ensure runtime permissions ────────────────────────────────────────────────
chown -R www-data:www-data "${MOODLE_DATA}"

# ── Document root (Moodle 5.x uses a public/ subdirectory) ───────────────────
if [ -d "${MOODLE_DIR}/public" ]; then
    echo "[moodle] Moodle 5.x structure detected — DocumentRoot set to ${MOODLE_DIR}/public"
    export MOODLE_DOCROOT="${MOODLE_DIR}/public"
else
    export MOODLE_DOCROOT="${MOODLE_DIR}"
fi

echo "[moodle] Starting Apache ..."
exec "$@"
