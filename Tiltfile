# -*- mode: Python -*-
# =============================================================================
# Tiltfile — Moodle Stack on Kubernetes (Minikube + Tilt)
# =============================================================================
# This configuration orchestrates a full Moodle LMS stack on Kubernetes using
# Tilt and minikube. It handles multi-version deployments (3.8, 4.5, 5.2) with
# automatic rebuilds on Dockerfile changes.
#
# Services started automatically on `tilt up`:
#   • mysql       — MySQL 8.4                           → localhost:$MYSQL_PORT
#   • postgres    — PostgreSQL 17                       → localhost:$POSTGRES_PORT
#   • redis       — Redis 7                             → localhost:$REDIS_PORT
#   • phpmyadmin  — phpMyAdmin (MySQL admin UI)         → http://localhost:$PHPMYADMIN_PORT
#   • pgadmin     — pgAdmin 4 (PostgreSQL admin UI)     → http://localhost:$PGADMIN_PORT
#
# On-demand (manual trigger via Tilt UI ▶):
#   • moodle38    — Moodle 3.8  (PHP 7.4)               → http://localhost:$MOODLE38_PORT
#   • moodle45    — Moodle 4.5  (PHP 8.2)               → http://localhost:$MOODLE45_PORT
#   • moodle52    — Moodle 5.2  (PHP 8.3)               → http://localhost:$MOODLE52_PORT
#
# Quick start:
#   1. Start minikube: minikube start
#   2. Initialize volumes: ./scripts/setup-volumes.sh
#   3. Start Tilt: tilt up
#   4. Open Tilt UI: http://localhost:10350
#   5. Trigger Moodle instances manually from the UI
# =============================================================================

# =============================================================================
# Configuration & Validation
# =============================================================================

# Restrict to minikube cluster (safety check)
allow_k8s_contexts('minikube')

# Load environment from .env file
load('ext://dotenv', 'dotenv')
dotenv()

# Kubernetes namespace
k8s_namespace = 'moodle'

def env_or_default(name, default):
    return local("sh -c 'value=\"${%s:-%s}\"; printf \"%%s\" \"$value\"'" % (name, default), quiet=True)


def render_env_template(src, dst):
    local('mkdir -p .tilt-generated', quiet=True)
    local('envsubst < %s > %s' % (src, dst), quiet=True)
    return dst


mysql_port = env_or_default('MYSQL_PORT', '3306')
postgres_port = env_or_default('POSTGRES_PORT', '5432')
redis_port = env_or_default('REDIS_PORT', '6379')
phpmyadmin_port = env_or_default('PHPMYADMIN_PORT', '8081')
pgadmin_port = env_or_default('PGADMIN_PORT', '8082')
moodle38_http_port = env_or_default('MOODLE38_PORT', '8080')
moodle38_https_port = env_or_default('MOODLE38_HTTPS_PORT', '8443')
moodle45_http_port = env_or_default('MOODLE45_PORT', '8090')
moodle45_https_port = env_or_default('MOODLE45_HTTPS_PORT', '8453')
moodle52_http_port = env_or_default('MOODLE52_PORT', '8091')
moodle52_https_port = env_or_default('MOODLE52_HTTPS_PORT', '8454')

# =============================================================================
# Kubernetes Manifests
# =============================================================================

# Load all K8s manifests (order matters: namespaces first, then configmaps, then resources)
k8s_yaml([
    'k8s/namespace.yaml',
    render_env_template('k8s/configmaps/shared-config.yaml', '.tilt-generated/shared-config.yaml'),
    'k8s/configmaps/mysql-init-sql.yaml',
    'k8s/configmaps/postgres-init-script.yaml',
    render_env_template('k8s/configmaps/moodle-config.yaml', '.tilt-generated/moodle-config.yaml'),
    'k8s/volumes/pvc.yaml',
    'k8s/base/mysql.yaml',
    'k8s/base/postgres.yaml',
    'k8s/base/redis.yaml',
    'k8s/base/admin-uis.yaml',
    'k8s/moodle/moodle-deployments.yaml',
    'k8s/moodle/moodle-services.yaml',
])

# =============================================================================
# Docker Image Builds
# =============================================================================

# Helper function to build Moodle images for each version
def build_moodle_image(version, php_version, moodle_branch):
    """Build Moodle Docker image for a specific version.

    The Moodle source is baked into the image from moodlefiles/moodle<version>
    (fast local overlay reads for the CLI installer) and kept up to date at
    runtime via live_update — which syncs changed files over the Tilt API
    instead of the slow 9p host mount that was previously used.

    The build context is the repo root because live_update sync() paths must be
    children of the build context; `only` scopes the context (and file watching)
    to just this version's source plus the shared moodle/ build assets.
    """
    src = 'moodlefiles/moodle%s' % version
    docker_build(
        'tilt-moodle:moodle%s' % version,
        '.',
        dockerfile='moodle/Dockerfile',
        build_args={
            'PHP_VERSION': php_version,
            'MOODLE_BRANCH': moodle_branch,
            'MOODLE_SRC': src,
        },
        only=['moodle', src],
        live_update=[
            # Editing build assets can't be hot-synced — force a full rebuild.
            fall_back_on([
                'moodle/Dockerfile',
                'moodle/entrypoint.sh',
                'moodle/apache-moodle.conf',
            ]),
            # Sync source edits straight into the running container.
            sync(src, '/var/www/html'),
            # Restore ownership on the freshly-synced files.
            run('chown -R www-data:www-data /var/www/html'),
        ],
    )

# Build images for all Moodle versions
build_moodle_image(
    '38',
    env_or_default('MOODLE38_PHP_VERSION', '7.4'),
    env_or_default('MOODLE38_BRANCH', 'MOODLE_38_STABLE'),
)
build_moodle_image(
    '45',
    env_or_default('MOODLE45_PHP_VERSION', '8.2'),
    env_or_default('MOODLE45_BRANCH', 'MOODLE_405_STABLE'),
)
build_moodle_image(
    '52',
    env_or_default('MOODLE52_PHP_VERSION', '8.3'),
    env_or_default('MOODLE52_BRANCH', 'MOODLE_502_STABLE'),
)

# =============================================================================
# Kubernetes Resource Configuration
# =============================================================================

# ── Database Services (auto-start) ──────────────────────────────────────────
k8s_resource(
    'mysql',
    labels=['databases'],
    port_forwards=['%s:3306' % mysql_port],
)

k8s_resource(
    'postgres',
    labels=['databases'],
    port_forwards=['%s:5432' % postgres_port],
)

k8s_resource(
    'redis',
    labels=['databases'],
    port_forwards=['%s:6379' % redis_port],
)

# ── Admin UI Services (auto-start, depend on databases) ────────────────────
k8s_resource(
    'phpmyadmin',
    labels=['admin-tools'],
    resource_deps=['mysql'],
    port_forwards=['%s:80' % phpmyadmin_port],
    links=[link('http://localhost:%s' % phpmyadmin_port, 'phpMyAdmin')],
)

k8s_resource(
    'pgadmin',
    labels=['admin-tools'],
    resource_deps=['postgres'],
    port_forwards=['%s:80' % pgadmin_port],
    links=[link('http://localhost:%s' % pgadmin_port, 'pgAdmin')],
)

# ── Moodle 3.8 (on-demand, manual trigger) ──────────────────────────────────
k8s_resource(
    'moodle38',
    labels=['moodle'],
    resource_deps=['mysql', 'postgres', 'redis', 'localhost-tls'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    port_forwards=['%s:80' % moodle38_http_port, '%s:443' % moodle38_https_port],
    links=[
        link('http://localhost:%s' % moodle38_http_port, 'Moodle 3.8 (HTTP)'),
        link('https://localhost:%s' % moodle38_https_port, 'Moodle 3.8 (HTTPS - self-signed)'),
    ],
)

# ── Moodle 4.5 (on-demand, manual trigger) ──────────────────────────────────
k8s_resource(
    'moodle45',
    labels=['moodle'],
    resource_deps=['mysql', 'postgres', 'redis', 'localhost-tls'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    port_forwards=['%s:80' % moodle45_http_port, '%s:443' % moodle45_https_port],
    links=[
        link('http://localhost:%s' % moodle45_http_port, 'Moodle 4.5 (HTTP)'),
        link('https://localhost:%s' % moodle45_https_port, 'Moodle 4.5 (HTTPS - self-signed)'),
    ],
)

# ── Moodle 5.2 (on-demand, manual trigger) ──────────────────────────────────
k8s_resource(
    'moodle52',
    labels=['moodle'],
    resource_deps=['mysql', 'postgres', 'redis', 'localhost-tls'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    port_forwards=['%s:80' % moodle52_http_port, '%s:443' % moodle52_https_port],
    links=[
        link('http://localhost:%s' % moodle52_http_port, 'Moodle 5.2 (HTTP)'),
        link('https://localhost:%s' % moodle52_https_port, 'Moodle 5.2 (HTTPS - self-signed)'),
    ],
)

# =============================================================================
# Local Resources (Setup & Validation)
# =============================================================================

local_resource(
    'localhost-tls',
    cmd='bash ./scripts/setup-localhost-cert.sh',
    deps=['scripts/setup-localhost-cert.sh'],
)

# Helper functions for resetting Moodle databases

def mysql_reset_cmd(dbname):
    root_password = env_or_default('MYSQL_ROOT_PASSWORD', 'rootpassword')
    return 'kubectl exec -n %s deploy/mysql -- mysql -uroot -p%s -e "DROP DATABASE IF EXISTS %s;" && kubectl exec -n %s deploy/mysql -- bash -lc "mysql -uroot -p%s < /docker-entrypoint-initdb.d/init.sql"' % (
        k8s_namespace,
        root_password,
        dbname,
        k8s_namespace,
        root_password,
    )


def mysql_reset_all_cmd():
    root_password = env_or_default('MYSQL_ROOT_PASSWORD', 'rootpassword')
    return 'kubectl exec -n %s deploy/mysql -- mysql -uroot -p%s -e "DROP DATABASE IF EXISTS moodle38; DROP DATABASE IF EXISTS moodle45; DROP DATABASE IF EXISTS moodle52;" && kubectl exec -n %s deploy/mysql -- bash -lc "mysql -uroot -p%s < /docker-entrypoint-initdb.d/init.sql"' % (
        k8s_namespace,
        root_password,
        k8s_namespace,
        root_password,
    )


def postgres_reset_cmd(dbname):
    pg_password = env_or_default('POSTGRES_PASSWORD', 'moodlepassword')
    pg_user = env_or_default('POSTGRES_USER', 'moodle')
    return 'kubectl exec -n %s deploy/postgres -- env PGPASSWORD=%s bash -lc \'psql -v ON_ERROR_STOP=1 --username "%s" --dbname "postgres" -c "DROP DATABASE IF EXISTS %s;" && /docker-entrypoint-initdb.d/init.sh\'' % (
        k8s_namespace,
        pg_password,
        pg_user,
        dbname,
    )


def postgres_reset_all_cmd():
    pg_password = env_or_default('POSTGRES_PASSWORD', 'moodlepassword')
    pg_user = env_or_default('POSTGRES_USER', 'moodle')
    return 'kubectl exec -n %s deploy/postgres -- env PGPASSWORD=%s bash -lc \'psql -v ON_ERROR_STOP=1 --username "%s" --dbname "postgres" -c "DROP DATABASE IF EXISTS moodle38;" -c "DROP DATABASE IF EXISTS moodle45;" -c "DROP DATABASE IF EXISTS moodle52;" && /docker-entrypoint-initdb.d/init.sh\'' % (
        k8s_namespace,
        pg_password,
        pg_user,
    )


# Check minikube status at startup
local_resource(
    'minikube-check',
    cmd='minikube status > /dev/null 2>&1 && echo "✓ minikube is running" || (echo "✗ minikube is not running" && exit 1)',
    labels=['checks'],
    trigger_mode=TRIGGER_MODE_MANUAL,
)

local_resource(
    'reset-mysql-moodle38-db',
    cmd=mysql_reset_cmd('moodle38'),
    labels=['db-reset'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['mysql'],
)

local_resource(
    'reset-mysql-moodle45-db',
    cmd=mysql_reset_cmd('moodle45'),
    labels=['db-reset'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['mysql'],
)

local_resource(
    'reset-mysql-moodle52-db',
    cmd=mysql_reset_cmd('moodle52'),
    labels=['db-reset'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['mysql'],
)

local_resource(
    'reset-mysql-all-moodle-dbs',
    cmd=mysql_reset_all_cmd(),
    labels=['db-reset'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['mysql'],
)

local_resource(
    'reset-postgres-moodle38-db',
    cmd=postgres_reset_cmd('moodle38'),
    labels=['db-reset'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['postgres'],
)

local_resource(
    'reset-postgres-moodle45-db',
    cmd=postgres_reset_cmd('moodle45'),
    labels=['db-reset'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['postgres'],
)

local_resource(
    'reset-postgres-moodle52-db',
    cmd=postgres_reset_cmd('moodle52'),
    labels=['db-reset'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['postgres'],
)

local_resource(
    'reset-postgres-all-moodle-dbs',
    cmd=postgres_reset_all_cmd(),
    labels=['db-reset'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['postgres'],
)

# =============================================================================
# Tilt Dashboard Configuration
# =============================================================================

# No unsupported config fields are used for this Tilt version.
