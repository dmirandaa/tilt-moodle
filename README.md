# Moodle Stack on Kubernetes with Tilt

This repository runs a local multi-version Moodle platform on Minikube using Tilt.

It provides:
- Moodle 3.8 (PHP 7.4)
- Moodle 4.5 (PHP 8.2)
- Moodle 5.2 (PHP 8.4)
- MySQL, PostgreSQL, Redis
- phpMyAdmin and pgAdmin
- Persistent data and config volumes
- Trusted HTTPS on localhost via mkcert automation

## What You Get

- A single local Kubernetes stack for Moodle development and testing
- One command workflow for bootstrap + run
- Manual trigger control for each Moodle version in Tilt
- Live source sync from local `moodlefiles/` into running containers
- Persistent `config.php` and moodledata storage per Moodle instance

## System Requirements

## Host OS

- Linux (recommended)
- macOS (works, commands may differ for package installs)
- WSL2 (works, but Docker/Minikube networking setup must be correct)

Windows compatibility disclaimer:
- Native Windows (without WSL2) is not fully supported and may have compatibility issues with tooling, filesystem behavior, and local networking.
- For Windows hosts, use WSL2 and run the full stack from inside the Linux environment.

## Required Tools

- Docker
- Minikube
- kubectl
- Tilt
- Git

## Recommended Tools

- mkcert
- libnss3-tools (for Chrome/Firefox NSS trust import on Linux)

## Minimum Suggested Host Resources

- CPU: 4 cores
- RAM: 8 GB
- Free disk: 30 GB+

## Install Dependencies (Ubuntu/Debian Example)

```bash
sudo apt update
sudo apt install -y docker.io git curl ca-certificates

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

# tilt
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash

# trusted localhost TLS tooling
sudo apt install -y mkcert libnss3-tools
```

## Install Dependencies (macOS Homebrew Example)

```bash
# Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# core tools
brew install docker kubectl minikube tilt-dev/tap/tilt git mkcert nss

# trust local CA for localhost certificates
mkcert -install
```

Notes for macOS:
- Docker Desktop is required for the Docker driver.
- If `brew install docker` does not provide the CLI in your shell, install Docker Desktop and ensure `docker` is in `PATH`.

Verify:

```bash
docker --version
minikube version
kubectl version --client
tilt version
git --version
mkcert --version
```

## Initial Setup

## 1. Clone Repository

```bash
git clone https://github.com/dmirandaa/tilt-moodle.git
cd tilt-moodle
```

## 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` as needed.

Most important variables:
- Moodle ports: `MOODLE38_PORT`, `MOODLE45_PORT`, `MOODLE52_PORT`
- Moodle HTTPS ports: `MOODLE38_HTTPS_PORT`, `MOODLE45_HTTPS_PORT`, `MOODLE52_HTTPS_PORT`
- DB backend choice: `MOODLE_DB_TYPE` (`mysqli` or `pgsql`)
- Redis sessions: `MOODLE_REDIS_SESSION` (`true` or `false`)

## 3. Start Minikube

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
```

## 4. Prepare Volumes and Local Moodle Source

```bash
chmod +x ./scripts/setup-volumes.sh
./scripts/setup-volumes.sh
```

What this does:
- Ensures local source trees exist in `moodlefiles/moodle38`, `moodlefiles/moodle45`, `moodlefiles/moodle52`
- Clones Moodle branches when missing
- Creates required hostPath directories in Minikube under `/mnt/moodle-volumes/...`

## 5. Install mkcert Local CA (One-Time, Recommended)

```bash
mkcert -install
```

Tilt also runs automatic TLS setup through `scripts/setup-localhost-cert.sh`.

That script:
- Generates localhost cert and key in `.certs/`
- Imports CA into Chrome and Firefox NSS DBs when possible
- Imports CA into system trust store when permission is available
- Creates Kubernetes TLS secret `moodle-localhost-tls`

## Run the Stack

```bash
tilt up
```

Tilt UI opens at:

- http://localhost:10350

Behavior on startup:
- Databases and admin UIs start automatically
- Moodle instances are manual trigger resources

Trigger Moodle resources from Tilt UI or CLI:

```bash
tilt trigger moodle38
tilt trigger moodle45
tilt trigger moodle52
```

## Service Endpoints

- Moodle 3.8 HTTP: http://localhost:8080
- Moodle 3.8 HTTPS: https://localhost:8443
- Moodle 4.5 HTTP: http://localhost:8090
- Moodle 4.5 HTTPS: https://localhost:8453
- Moodle 5.2 HTTP: http://localhost:8091
- Moodle 5.2 HTTPS: https://localhost:8454
- phpMyAdmin: http://localhost:8081
- pgAdmin: http://localhost:8082
- MySQL: localhost:3306
- PostgreSQL: localhost:5432
- Redis: localhost:6379

Ports above are defaults from `.env.example`.

## Common Usage Examples

## Check Pod Status

```bash
kubectl get pods -n moodle
```

## Follow Logs

```bash
kubectl logs -f deployment/mysql -n moodle
kubectl logs -f deployment/moodle52 -n moodle
```

## Verify Moodle Deployment Rollout

```bash
kubectl rollout status deployment/moodle52 -n moodle --timeout=10m
```

## Restart One Service

```bash
kubectl rollout restart deployment/redis -n moodle
```

## Reset a Moodle Database from Tilt Local Resources

Use Tilt UI local resources:
- `reset-mysql-moodle38-db`
- `reset-mysql-moodle45-db`
- `reset-mysql-moodle52-db`
- `reset-mysql-all-moodle-dbs`
- `reset-postgres-moodle38-db`
- `reset-postgres-moodle45-db`
- `reset-postgres-moodle52-db`
- `reset-postgres-all-moodle-dbs`

## TLS and Browser Trust

HTTPS certificates are provided by mkcert and mounted into Moodle pods through secret `moodle-localhost-tls`.

If browser trust is still not active:

```bash
mkcert -install
bash ./scripts/setup-localhost-cert.sh
```

If system trust import requires elevation, run:

```bash
sudo bash ./scripts/setup-localhost-cert.sh
```

## Persistence Model

This stack uses static Kubernetes PersistentVolumes with `Retain` policy for all major services.

Data survives `tilt down` and `tilt up` cycles.

Volume data paths inside Minikube host:
- `/mnt/moodle-volumes/mysql-data`
- `/mnt/moodle-volumes/postgres-data`
- `/mnt/moodle-volumes/redis-data`
- `/mnt/moodle-volumes/pgadmin-data`
- `/mnt/moodle-volumes/moodle38-data`
- `/mnt/moodle-volumes/moodle38-config`
- `/mnt/moodle-volumes/moodle45-data`
- `/mnt/moodle-volumes/moodle45-config`
- `/mnt/moodle-volumes/moodle52-data`
- `/mnt/moodle-volumes/moodle52-config`

Moodle config behavior:
- On first install, `config.php` is created by CLI installer
- Canonical persisted copy is stored in `/var/www/moodle_config/config.php`
- On next startup, persisted config is restored to `/var/www/html/config.php`

## Daily Workflow

## Start

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
tilt up
```

## Work on Moodle Source

Edit files in:
- `moodlefiles/moodle38`
- `moodlefiles/moodle45`
- `moodlefiles/moodle52`

Tilt `live_update` syncs changes into `/var/www/html` in running pods.

## Stop

```bash
tilt down
```

## Full Cleanup

```bash
kubectl delete namespace moodle
minikube stop
# Optional full removal
minikube delete
```

## Troubleshooting

## Pods Pending with PVC Errors

Check claims and volumes:

```bash
kubectl get pvc -n moodle
kubectl get pv
kubectl describe pvc -n moodle <claim-name>
```

Re-run setup to ensure Minikube host directories exist:

```bash
./scripts/setup-volumes.sh
```

## Moodle Stuck Waiting for Install or Reinstalling

Inspect deployment logs:

```bash
kubectl logs -f deployment/moodle38 -n moodle
```

Check persisted config file inside pod:

```bash
kubectl exec -it deployment/moodle38 -n moodle -- ls -lah /var/www/moodle_config
```

## HTTPS Still Untrusted in Browser

```bash
mkcert -install
bash ./scripts/setup-localhost-cert.sh
```

For Linux NSS stores, ensure `certutil` is available:

```bash
sudo apt install -y libnss3-tools
```

## Useful Commands

```bash
# Tilt
tilt up
tilt down
tilt trigger moodle38
tilt trigger moodle45
tilt trigger moodle52

# Kubernetes
kubectl get ns,pods,svc,pvc -n moodle
kubectl describe pod <pod-name> -n moodle
kubectl logs deployment/<deployment-name> -n moodle -f
kubectl exec -it deployment/<deployment-name> -n moodle -- bash

# Minikube
minikube status
minikube ssh
minikube stop
minikube delete
```

## Project Structure

```text
tilt-moodle/
├── Tiltfile
├── .env.example
├── k8s/
│   ├── namespace.yaml
│   ├── configmaps/
│   ├── volumes/
│   ├── base/
│   └── moodle/
├── scripts/
│   ├── setup-volumes.sh
│   └── setup-localhost-cert.sh
├── moodle/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── apache-moodle.conf
├── moodlefiles/
│   ├── moodle38/
│   ├── moodle45/
│   └── moodle52/
├── mysql/
│   └── init.sql
└── postgres/
    └── init.sh
```
