# -*- mode: Python -*-
# =============================================================================
# Tiltfile — Moodle Stack
# =============================================================================
# Services started automatically on `tilt up`:
#   • mysql       — MySQL 8                             → localhost:3306
#   • postgres    — PostgreSQL 16                       → localhost:5432
#   • phpmyadmin  — phpMyAdmin (MySQL admin UI)         → http://localhost:8081
#   • pgadmin     — pgAdmin 4 (PostgreSQL admin UI)     → http://localhost:8082
#
# On-demand (NOT started automatically — use the Tilt UI ▶ or `tilt trigger`):
#   • moodle38    — Moodle 3.8  (PHP 7.4)               → http://localhost:8080
#   • moodle45    — Moodle 4.5  (PHP 8.2)               → http://localhost:8090
#   • moodle52    — Moodle 5.2  (PHP 8.3)               → http://localhost:8091
#
# Compatible with Windows and Linux.
#
# Quick start:
#   1. Copy .env.example to .env and adjust values.
#   2. Run: tilt up
#   3. Start a Moodle instance from the Tilt UI when ready.
# =============================================================================

# Load the Docker Compose project.
# All Moodle profiles are activated so Tilt can manage them from the UI;
# auto_init=False below prevents them from starting on `tilt up`.
docker_compose('docker-compose.yml', profiles=['moodle38', 'moodle45', 'moodle52'])

# ── Databases ────────────────────────────────────────────────────────────────
dc_resource(
    'mysql',
    labels=['databases'],
)

dc_resource(
    'postgres',
    labels=['databases'],
)

# ── Moodle Instances (on-demand) ─────────────────────────────────────────────
# auto_init=False  — not started by `tilt up`
# TRIGGER_MODE_MANUAL — not rebuilt automatically on file changes
#
# To start an instance:
#   • Click ▶ next to the resource in the Tilt UI, or
#   • Run: tilt trigger moodle38 | moodle45 | moodle52

dc_resource(
    'moodle38',
    labels=['application'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['mysql', 'postgres'],
    links=[
        link('http://localhost:8080',  'Moodle 3.8'),
        link('https://localhost:8443', 'Moodle 3.8 (HTTPS)'),
    ],
)

dc_resource(
    'moodle45',
    labels=['application'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['mysql', 'postgres'],
    links=[
        link('http://localhost:8090',  'Moodle 4.5'),
        link('https://localhost:8453', 'Moodle 4.5 (HTTPS)'),
    ],
)

dc_resource(
    'moodle52',
    labels=['application'],
    auto_init=False,
    trigger_mode=TRIGGER_MODE_MANUAL,
    resource_deps=['mysql', 'postgres'],
    links=[
        link('http://localhost:8091',  'Moodle 5.2'),
        link('https://localhost:8454', 'Moodle 5.2 (HTTPS)'),
    ],
)

# ── Admin Interfaces ─────────────────────────────────────────────────────────
dc_resource(
    'phpmyadmin',
    labels=['admin-tools'],
    resource_deps=['mysql'],
    links=[
        link('http://localhost:8081', 'phpMyAdmin'),
    ],
)

dc_resource(
    'pgadmin',
    labels=['admin-tools'],
    resource_deps=['postgres'],
    links=[
        link('http://localhost:8082', 'pgAdmin'),
    ],
)
