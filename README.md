# Moodle Stack — Tilt

Deploys a full Moodle LMS environment using [Tilt](https://tilt.dev/) and Docker Compose.  
Compatible with **Windows** and **Linux**.

## Prerequisites

### Docker Desktop

1. Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop/) for your OS.
2. Start Docker Desktop and wait until the engine is running (the taskbar icon turns steady).
3. _(Windows only)_ Go to **Settings → General** and ensure **"Use the WSL 2 based engine"** is enabled for best performance.

Verify the installation:

```bash
docker --version
docker compose version
```

### Tilt

With Docker Desktop running, install the Tilt CLI:

**Windows (PowerShell — run as Administrator):**

```powershell
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.ps1'))
```

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
```

Verify:

```bash
tilt version
```

> Full installation docs: <https://docs.tilt.dev/install.html>

## Services

| Service       | URL / Port                                     | Notes                                                   |
| ------------- | ---------------------------------------------- | ------------------------------------------------------- |
| Moodle 3.8 ¹  | http://localhost:8080 · https://localhost:8443 | On-demand — PHP 7.4, branch `MOODLE_38_STABLE`          |
| phpMyAdmin    | http://localhost:8081                          | Connects to MySQL                                       |
| pgAdmin       | http://localhost:8082                          | Login: `PGADMIN_EMAIL` / `PGADMIN_PASSWORD` from `.env` |
| MySQL 8       | localhost:3306                                 |                                                         |
| PostgreSQL 16 | localhost:5432                                 |                                                         |
| Redis 7       | localhost:6379                                 | Session/cache backend — always started                  |
| Moodle 4.5 ¹  | http://localhost:8090 · https://localhost:8453 | On-demand — PHP 8.2, branch `MOODLE_405_STABLE`         |
| Moodle 5.2 ¹  | http://localhost:8091 · https://localhost:8454 | On-demand — PHP 8.3, branch `MOODLE_502_STABLE`         |

¹ Not started by default; start from the Tilt UI ▶ or with `tilt trigger`. See [On-demand Moodle instances](#on-demand-moodle-instances).

## File Structure

```
tilt/
├── Tiltfile                   Tilt orchestration & service labels
├── docker-compose.yml         All service definitions
├── .env.example               Template — copy to .env and adjust before first run
├── mysql/
│   └── init.sql               Creates extra databases for on-demand instances
├── postgres/
│   └── init.sh                Creates extra databases for on-demand instances
└── moodle/
    ├── Dockerfile             PHP 7/8 + Apache2 + Moodle image
    ├── entrypoint.sh          First-boot installer & cron setup
    └── apache-moodle.conf     Apache VirtualHost config
```

## Quick Start

1. Copy `.env.example` to `.env` and adjust passwords and ports as needed.
2. Start the stack:
   ```bash
   tilt up
   ```
3. Open the Tilt UI at http://localhost:10350 to monitor all services.
4. Click ▶ next to a Moodle instance in the Tilt UI (e.g. `moodle38`) to start it, or run:
   ```bash
   tilt trigger moodle38
   ```
5. On first boot, Moodle runs the CLI installer automatically — this takes a few minutes.

To stop and remove containers (volumes are preserved):

```bash
tilt down
```

## PHP Versions

Each Moodle service has a fixed PHP version and branch set in `docker-compose.yml`:

| Service    | PHP | Branch              | Moodle version |
| ---------- | --- | ------------------- | -------------- |
| Moodle 3.8 | 7.4 | `MOODLE_38_STABLE`  | 3.8            |
| Moodle 4.5 | 8.2 | `MOODLE_405_STABLE` | 4.5 LTS        |
| Moodle 5.2 | 8.3 | `MOODLE_502_STABLE` | 5.2            |

The Dockerfile supports PHP **7.4**, **8.0**, **8.1**, **8.2**, and **8.3**. To add a custom instance, duplicate a service block in `docker-compose.yml` and adjust `PHP_VERSION` and `MOODLE_BRANCH`. After any build-arg change, rebuild:

```bash
docker compose build moodle38  # or moodle45 / moodle52
```

## Database Backend

Moodle defaults to **MySQL** (`MOODLE_DB_TYPE=mysqli`).  
To switch to **PostgreSQL**, update `.env`:

```env
MOODLE_DB_TYPE=pgsql
MOODLE_DB_HOST=postgres
MOODLE_DB_PORT=5432
```

## Redis Session Cache

A **Redis 7** container is always started on `tilt up` and joins the same `moodle_net`
network, making it available to all Moodle instances at hostname `redis`.

By default Moodle still uses its **file-based** session handler. To switch to Redis,
set the following in `.env` **before** starting a Moodle instance for the first time,
or before removing and recreating its `moodle_config` volume:

```env
MOODLE_REDIS_SESSION=true
```

On container startup the entrypoint injects the required `$CFG->session_redis_*` lines
into `config.php` automatically. The injection is **idempotent** — it is skipped if the
settings are already present, so it is safe across restarts.

| Variable               | Default | Description                                          |
| ---------------------- | ------- | ---------------------------------------------------- |
| `MOODLE_REDIS_SESSION` | `false` | Set to `true` to enable the Redis session handler    |
| `MOODLE_REDIS_HOST`    | `redis` | Redis hostname (container name on `moodle_net`)      |
| `MOODLE_REDIS_PORT`    | `6379`  | Redis port                                           |
| `REDIS_PORT`           | `6379`  | Host-side port exposed by the Redis container        |

> **Enabling Redis on an already-installed instance** — if the instance was previously
> started without Redis, set `MOODLE_REDIS_SESSION=true` and restart the container.
> The entrypoint will inject the Redis settings into the persisted `config.php` on the
> next boot without re-running the full installer.

To connect to Redis directly from the host:

```bash
docker exec -it moodle_redis redis-cli ping
```

## config.php Persistence

On first start the Moodle CLI installer generates `config.php` and stores it in the
`moodle_config` Docker volume. On subsequent starts it is symlinked back into the web
root, so container rebuilds do **not** re-run the installer as long as the database
volume is intact.

To perform a full reinstall, remove both volumes:

```bash
docker volume rm tilt_moodle38_config tilt_moodle38_data tilt_mysql_data
```

## On-demand Moodle Instances

All three Moodle versions are defined with Docker Compose
[profiles](https://docs.docker.com/compose/profiles/) so they are **not** started
by default.

| Instance   | Profile    | HTTP port | HTTPS port | PHP | Branch              |
| ---------- | ---------- | --------- | ---------- | --- | ------------------- |
| Moodle 3.8 | `moodle38` | 8080      | 8443       | 7.4 | `MOODLE_38_STABLE`  |
| Moodle 4.5 | `moodle45` | 8090      | 8453       | 8.2 | `MOODLE_405_STABLE` |
| Moodle 5.2 | `moodle52` | 8091      | 8454       | 8.3 | `MOODLE_502_STABLE` |

**First-time setup** — all databases (`moodle38`, `moodle45`, `moodle52`) are created
automatically by `mysql/init.sql` and `postgres/init.sh` when the database containers are
first initialised.  
If the `mysql_data` volume already exists, create the MySQL databases manually:

```bash
docker exec -i moodle_mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" <<'SQL'
CREATE DATABASE IF NOT EXISTS moodle38 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS moodle45 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS moodle52 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON moodle38.* TO 'moodle'@'%';
GRANT ALL PRIVILEGES ON moodle45.* TO 'moodle'@'%';
GRANT ALL PRIVILEGES ON moodle52.* TO 'moodle'@'%';
FLUSH PRIVILEGES;
SQL
```

**Start an instance:**

```bash
# Moodle 3.8
docker compose --profile moodle38 up moodle38

# Moodle 4.5 only (builds image on first run)
docker compose --profile moodle45 up moodle45

# Moodle 5.2 only
docker compose --profile moodle52 up moodle52

# Both 4.5 and 5.2 at once
docker compose --profile moodle45 --profile moodle52 up
```

Ports and the WWWROOT can be overridden via `.env` using
`MOODLE45_PORT`, `MOODLE45_HTTPS_PORT`, `MOODLE52_PORT`, and `MOODLE52_HTTPS_PORT`.

To reset an on-demand instance, remove its volumes:

```bash
docker volume rm tilt_moodle38_config tilt_moodle38_data
docker volume rm tilt_moodle45_config tilt_moodle45_data
docker volume rm tilt_moodle52_config tilt_moodle52_data
```

## Design Notes

- **PHP 7 vs PHP 8 GD extension** — the Dockerfile detects the PHP major version at
  build time and selects the correct `docker-php-ext-configure gd` flags
  (`--with-freetype-dir` for PHP 7, `--with-freetype` for PHP 8).
- **Windows/Linux compatibility** — named volumes avoid OS-specific bind-mount paths.
  The Dockerfile strips Windows `\r` characters from `entrypoint.sh` at build time via
  `sed`, so the script works correctly inside the Linux container regardless of where
  the source was edited.
- **Health checks** — each Moodle service only starts after both `mysql` and `postgres`
  pass their health checks, preventing connection errors during initialisation.
- **Moodle cron** — a cron job running `admin/cli/cron.php` every minute is registered
  automatically on first boot.
