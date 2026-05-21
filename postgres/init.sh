#!/bin/bash
# =============================================================================
# PostgreSQL init — extra databases for on-demand Moodle instances
# =============================================================================
# This script runs once when the postgres container is first created.
# If the postgres_data volume already exists, remove it before restarting the
# stack so that this script is executed:
#   docker volume rm tilt_postgres_data
# =============================================================================
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    SELECT 'CREATE DATABASE moodle38'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'moodle38')\gexec

    SELECT 'CREATE DATABASE moodle45'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'moodle45')\gexec

    SELECT 'CREATE DATABASE moodle52'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'moodle52')\gexec

    GRANT ALL PRIVILEGES ON DATABASE moodle38 TO "$POSTGRES_USER";
    GRANT ALL PRIVILEGES ON DATABASE moodle45 TO "$POSTGRES_USER";
    GRANT ALL PRIVILEGES ON DATABASE moodle52 TO "$POSTGRES_USER";
EOSQL

echo "[postgres-init] Databases moodle38, moodle45, and moodle52 are ready."
