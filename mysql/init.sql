-- =============================================================================
-- MySQL init — extra databases for on-demand Moodle instances
-- =============================================================================
-- This script runs once when the mysql container is first created.
-- If the mysql_data volume already exists, remove it before restarting the
-- stack so that this script is executed:
--   docker volume rm tilt_mysql_data
-- =============================================================================

CREATE DATABASE IF NOT EXISTS moodle38
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS moodle45
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS moodle52
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Grant the shared Moodle DB user access to both extra databases.
-- Default user is 'moodle'; change if MOODLE_DB_USER is overridden in .env.
GRANT ALL PRIVILEGES ON moodle38.* TO 'moodle'@'%';
GRANT ALL PRIVILEGES ON moodle45.* TO 'moodle'@'%';
GRANT ALL PRIVILEGES ON moodle52.* TO 'moodle'@'%';

FLUSH PRIVILEGES;
