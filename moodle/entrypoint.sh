#!/bin/bash
# =============================================================================
# Moodle entrypoint
# =============================================================================
# Responsibilities:
#   1. Clone Moodle source if not already present (volume-mount or first run).
#   2. Wait for the configured database to accept connections.
#   3. On the very first start, run the Moodle CLI installer.
#   4. Persist config.php to a dedicated volume so it survives container
#      rebuilds while the database volume remains intact.
#   5. Install a cron job for Moodle's task scheduler.
#   6. Hand off to Apache (apache2-foreground).
# =============================================================================
set -e

MOODLE_DIR=/var/www/html
MOODLE_DATA=/var/www/moodledata
MOODLE_CONFIG_DIR=/var/www/moodle_config
MOODLE_CONFIG="${MOODLE_CONFIG_DIR}/config.php"
MOODLE_CONFIG_LINK="${MOODLE_DIR}/config.php"

# ── Ensure config directory exists and is writable ──────────────────────────
mkdir -p "${MOODLE_CONFIG_DIR}"
chown www-data:www-data "${MOODLE_CONFIG_DIR}"
chmod 770 "${MOODLE_CONFIG_DIR}"

# ── Debug: Verify volume mount is accessible ──────────────────────────────────
echo "[moodle] Config paths:"
echo "[moodle]   MOODLE_CONFIG_DIR (volume): ${MOODLE_CONFIG_DIR}"
echo "[moodle]   MOODLE_CONFIG (file):       ${MOODLE_CONFIG}"
echo "[moodle]   MOODLE_CONFIG_LINK (web):   ${MOODLE_CONFIG_LINK}"
if [ -d "${MOODLE_CONFIG_DIR}" ]; then
    echo "[moodle] ✓ Config directory is accessible"
    ls -ld "${MOODLE_CONFIG_DIR}"
else
    echo "[moodle] ✗ ERROR: Config directory is NOT accessible!"
fi

# ── Detect Moodle version structure early (Moodle 5.x have public/ subdirectory) ──
if [ -d "${MOODLE_DIR}/public" ]; then
    export MOODLE_DOCROOT="${MOODLE_DIR}/public"
else
    export MOODLE_DOCROOT="${MOODLE_DIR}"
fi

# ── Read env with fallbacks ───────────────────────────────────────────────────
DB_TYPE="${MOODLE_DB_TYPE:-mysqli}"
DB_HOST="${MOODLE_DB_HOST:-mysql}"
DB_PORT="${MOODLE_DB_PORT:-3306}"
DB_NAME="${MOODLE_DB_NAME:-moodle}"
DB_USER="${MOODLE_DB_USER:-moodle}"
DB_PASS="${MOODLE_DB_PASSWORD:-moodlepassword}"
DB_PREFIX="${MOODLE_DB_PREFIX:-mdl_}"
WWWROOT="${MOODLE_WWWROOT:-http://localhost:8080}"
HTTPS_REDIRECT_BASE="${WWWROOT%/}"
ADMIN_USER="${MOODLE_ADMIN_USER:-admin}"
ADMIN_PASS="${MOODLE_ADMIN_PASSWORD:-password!}"
ADMIN_EMAIL="${MOODLE_ADMIN_EMAIL:-admin@example.com}"
SITE_NAME="${MOODLE_SITE_NAME:-Moodle LMS}"
SITE_SHORTNAME="${MOODLE_SITE_SHORTNAME:-moodle}"
REDIS_ENABLED="${MOODLE_REDIS_SESSION:-false}"
REDIS_HOST="${MOODLE_REDIS_HOST:-redis}"
REDIS_PORT="${MOODLE_REDIS_PORT:-6379}"
MOODLE_BRANCH="${MOODLE_BRANCH:-MOODLE_38_STABLE}"
MOODLE_SESSION_COOKIE_NAME="${MOODLE_SESSION_COOKIE_NAME:-MOODLESESSID}"

inject_redis_session() {
    local config_file="$1"
    if grep -q 'session_handler_class' "${config_file}" 2>/dev/null; then
        echo "[moodle] Redis session config already present — skipping."
        return
    fi
    echo "[moodle] Injecting Redis session config into config.php ..."
    local tmp_block tmp_out
    tmp_block=$(mktemp)
    tmp_out=$(mktemp)
    cat > "${tmp_block}" << EOF
// ── Redis session store ──────────────────────────────────────────────────────
\$CFG->session_handler_class              = '\\core\\session\\redis';
\$CFG->session_redis_host                 = '${REDIS_HOST}';
\$CFG->session_redis_port                 = ${REDIS_PORT};
\$CFG->session_redis_database             = 0;
\$CFG->session_redis_auth                 = '';
\$CFG->session_redis_acquire_lock_timeout = 120;
\$CFG->session_redis_lock_expire          = 7200;

EOF
    awk -v block="${tmp_block}" '
        /require_once\(/ && !done {
            while ((getline line < block) > 0) print line
            close(block)
            done=1
        }
        { print }
    ' "${config_file}" > "${tmp_out}"
    mv "${tmp_out}" "${config_file}"
    rm -f "${tmp_block}"
    echo "[moodle] Redis session config injected."
}

upsert_session_cookie() {
    local config_file="$1"
    local cookie_name="$2"

    if [ -z "${cookie_name}" ]; then
        echo "[moodle] Session cookie name is empty — skipping config update."
        return
    fi

    if grep -q '^\$CFG->sessioncookie[[:space:]]*=' "${config_file}" 2>/dev/null; then
        echo "[moodle] Updating existing session cookie name in config.php ..."
        local tmp_out
        tmp_out=$(mktemp)
        awk -v cookie="${cookie_name}" '
            /^\$CFG->sessioncookie[[:space:]]*=/ && !done {
                print "$CFG->sessioncookie               = '\''" cookie "'\'';"
                done=1
                next
            }
            { print }
        ' "${config_file}" > "${tmp_out}"
        mv "${tmp_out}" "${config_file}"
        return
    fi

    echo "[moodle] Injecting session cookie name into config.php ..."
    local tmp_block tmp_out
    tmp_block=$(mktemp)
    tmp_out=$(mktemp)
    cat > "${tmp_block}" << EOF
// ── Session cookie name (instance isolation) ────────────────────────────────
\$CFG->sessioncookie               = '${cookie_name}';

EOF
    awk -v block="${tmp_block}" '
        /require_once\(/ && !done {
            while ((getline line < block) > 0) print line
            close(block)
            done=1
        }
        { print }
    ' "${config_file}" > "${tmp_out}"
    mv "${tmp_out}" "${config_file}"
    rm -f "${tmp_block}"
    echo "[moodle] Session cookie name configured: ${cookie_name}"
}

# ── Clone Moodle source if not present ────────────────────────────────────────
# This handles two cases:
#   1. K8s with volume mounts: source is mounted from host, directory exists but may be empty
#   2. First-time container startup: directory exists but is empty
# Check for config-dist.php as it exists in all Moodle versions (including 5.x with public/ structure)
if [ ! -f "${MOODLE_DIR}/config-dist.php" ]; then
    echo "[moodle] Moodle source not found at ${MOODLE_DIR} — cloning from git ..."
    # Ensure directory is empty before clone (in case of permission issues)
    rm -rf "${MOODLE_DIR}"/*
    git clone --depth=1 --branch "${MOODLE_BRANCH}" \
        https://github.com/moodle/moodle.git "${MOODLE_DIR}"
    chown -R www-data:www-data "${MOODLE_DIR}"
    find "${MOODLE_DIR}" -type d -exec chmod 755 {} +
    find "${MOODLE_DIR}" -type f -exec chmod 644 {} +
    echo "[moodle] Moodle source cloned successfully."
else
    echo "[moodle] Moodle source found — skipping clone."
fi

# ── Unified config.php flow for all Moodle versions ──────────────────────────
# Canonical storage is the config volume; runtime copy lives in the web root.
# This prevents local source config.php from changing install behavior between
# Moodle versions.
install_moodle_cli() {
    echo "[moodle] No persisted config.php found — running Moodle CLI installer ..."
    echo "[moodle] This may take a few minutes on first boot."

    # Ensure correct ownership on writable directories
    chown -R www-data:www-data "${MOODLE_DATA}" "${MOODLE_CONFIG_DIR}" || true
    chmod 770 "${MOODLE_DATA}" "${MOODLE_CONFIG_DIR}" || true

    # Debug: print variables before installer
    echo "[moodle] Debug: WWWROOT='${WWWROOT}' DB_TYPE='${DB_TYPE}' DB_HOST='${DB_HOST}'"
    echo "[moodle] Debug: MOODLE_DB_HOST env='${MOODLE_DB_HOST}'"

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

    # Guard: verify installer actually produced config.php before touching it.
    if [ ! -f "${MOODLE_CONFIG_LINK}" ]; then
        echo "[moodle] ERROR: installer finished but ${MOODLE_CONFIG_LINK} was not created."
        exit 1
    fi

    chown www-data:www-data "${MOODLE_CONFIG_LINK}"
    chmod 640 "${MOODLE_CONFIG_LINK}"
    echo "[moodle] Installation complete."
}

# ── Config bootstrap ──────────────────────────────────────────────────────────
# Priority:
#   1. Persisted config on moodleXX-config volume  → restore to web root
#   2. No persisted config, no web root config     → run installer (first boot)
# A web-root-only config.php never exists on a clean image (Dockerfile removes
# it) so there is no third branch; the elif is a safety net only.
echo "[moodle] Checking for persisted config..."
if [ -f "${MOODLE_CONFIG}" ]; then
    echo "[moodle] ✓ Found persisted config at ${MOODLE_CONFIG}"
    echo "[moodle]   Restoring config.php from persistent volume to web root."
    ls -lh "${MOODLE_CONFIG}"
    cp -f "${MOODLE_CONFIG}" "${MOODLE_CONFIG_LINK}"
    chown www-data:www-data "${MOODLE_CONFIG_LINK}"
    chmod 640 "${MOODLE_CONFIG_LINK}"
    echo "[moodle] ✓ Config restored successfully"
elif [ -f "${MOODLE_CONFIG_LINK}" ]; then
    # Safety net: config in web root but not yet on volume (e.g. volume wiped).
    echo "[moodle] ⚠ WARNING: config.php found in web root but not on volume — seeding volume."
    ls -lh "${MOODLE_CONFIG_LINK}"
else
    echo "[moodle] ✗ No persisted config found. Running Moodle CLI installer..."
    install_moodle_cli
fi

# ── Post-processing: inject runtime settings into config.php ─────────────────
upsert_session_cookie "${MOODLE_CONFIG_LINK}" "${MOODLE_SESSION_COOKIE_NAME}"

if [ "${REDIS_ENABLED}" = "true" ]; then
    inject_redis_session "${MOODLE_CONFIG_LINK}"
fi

# ── Persist final config.php to volume ───────────────────────────────────────
# This is the single, definitive write. It captures the installer-generated
# config PLUS any runtime injections (session cookie, redis) in one step.
echo "[moodle] ──────────────────────────────────────────────────────────────────"
echo "[moodle] PERSISTENCE STEP: Writing final config.php to volume..."
echo "[moodle] ──────────────────────────────────────────────────────────────────"
echo "[moodle] Source (web root):       ${MOODLE_CONFIG_LINK}"
echo "[moodle] Destination (volume):    ${MOODLE_CONFIG}"

if [ ! -f "${MOODLE_CONFIG_LINK}" ]; then
    echo "[moodle] ✗ ERROR: ${MOODLE_CONFIG_LINK} does not exist — cannot persist."
    ls -lh "${MOODLE_DIR}" | head -20
    exit 1
fi
echo "[moodle] ✓ Source file exists:"
ls -lh "${MOODLE_CONFIG_LINK}"

if [ ! -d "${MOODLE_CONFIG_DIR}" ]; then
    echo "[moodle] ✗ ERROR: config volume ${MOODLE_CONFIG_DIR} is not mounted."
    exit 1
fi
echo "[moodle] ✓ Config volume is mounted:"
ls -ld "${MOODLE_CONFIG_DIR}"

echo "[moodle] Copying config.php..."
if ! cp -f "${MOODLE_CONFIG_LINK}" "${MOODLE_CONFIG}"; then
    echo "[moodle] ✗ ERROR: Failed to copy config.php to volume!"
    exit 1
fi
echo "[moodle] ✓ Copy successful:"
ls -lh "${MOODLE_CONFIG}"

chown www-data:www-data "${MOODLE_CONFIG_LINK}" "${MOODLE_CONFIG}"
chmod 640 "${MOODLE_CONFIG_LINK}" "${MOODLE_CONFIG}"
echo "[moodle] ✓ Permissions set"
echo "[moodle] ✓✓✓ Config persisted successfully to volume! ✓✓✓"

echo "[moodle] entrypoint: config handling complete, continuing startup."

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

# ── Update Apache VirtualHost with runtime placeholders ───────────────────────
# The apache-moodle.conf uses ${MOODLE_DOCROOT} and ${MOODLE_HTTPS_REDIRECT_BASE}
# placeholders which are not expanded by Apache at runtime.
sed -i 's|\${MOODLE_DOCROOT}|'"${MOODLE_DOCROOT}"'|g' /etc/apache2/sites-available/000-default.conf
sed -i 's|\${MOODLE_HTTPS_REDIRECT_BASE}|'"${HTTPS_REDIRECT_BASE}"'|g' /etc/apache2/sites-available/000-default.conf

echo "[moodle] Apache DocumentRoot configured to: ${MOODLE_DOCROOT}"
echo "[moodle] Apache HTTP redirect base configured to: ${HTTPS_REDIRECT_BASE}"
echo "[moodle] Starting Apache ..."
exec "$@"
