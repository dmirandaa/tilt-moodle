#!/bin/bash
set -euo pipefail

NAMESPACE="moodle"
SECRET_NAME="moodle-localhost-tls"
CERT_DIR=".certs"
CERT_FILE="${CERT_DIR}/localhost.crt"
KEY_FILE="${CERT_DIR}/localhost.key"
CA_NICKNAME="mkcert-local-ca"

log() {
  echo "[tls] $*"
}

warn() {
  echo "[tls] WARN: $*"
}

import_ca_to_nss_db() {
  local db_dir="$1"
  local ca_file="$2"

  if [[ ! -d "$db_dir" ]]; then
    return 0
  fi

  if ! command -v certutil >/dev/null 2>&1; then
    warn "certutil not found; skipping NSS import for ${db_dir}"
    return 0
  fi

  mkdir -p "$db_dir"

  # Replace existing entry for idempotency.
  certutil -d "sql:${db_dir}" -D -n "${CA_NICKNAME}" >/dev/null 2>&1 || true
  certutil -d "sql:${db_dir}" -A -n "${CA_NICKNAME}" -t "C,," -i "$ca_file" >/dev/null 2>&1 || {
    warn "failed to import CA into NSS DB ${db_dir}"
    return 0
  }

  log "Imported local CA into NSS DB: ${db_dir}"
}

ensure_certutil() {
  if command -v certutil >/dev/null 2>&1; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    warn "certutil not found; attempting to install libnss3-tools"
    sudo apt-get update -y >/dev/null 2>&1 || true
    sudo apt-get install -y libnss3-tools >/dev/null 2>&1 || {
      warn "automatic install of libnss3-tools failed"
      return 1
    }
    command -v certutil >/dev/null 2>&1 && return 0
  fi

  warn "certutil not found and cannot auto-install without passwordless sudo"
  return 1
}

import_ca_to_firefox_profiles() {
  local ca_file="$1"
  local roots=(
    "$HOME/.mozilla/firefox"
    "$HOME/snap/firefox/common/.mozilla/firefox"
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
  )

  local found=0
  local root
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    found=1
    while IFS= read -r -d '' profile; do
      import_ca_to_nss_db "$profile" "$ca_file"
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d \( -name '*.default*' -o -name '*.profile*' -o -name '*.release*' \) -print0 2>/dev/null)
  done

  if [[ "$found" -eq 0 ]]; then
    log "No Firefox profiles found; skipping Firefox trust import"
  fi
}

install_ca_to_system_store() {
  local ca_file="$1"
  local dst="/usr/local/share/ca-certificates/${CA_NICKNAME}.crt"

  if [[ "$(id -u)" -eq 0 ]]; then
    cp "$ca_file" "$dst"
    update-ca-certificates >/dev/null 2>&1 || warn "update-ca-certificates failed as root"
    log "Installed local CA into system trust store"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo cp "$ca_file" "$dst"
    sudo update-ca-certificates >/dev/null 2>&1 || warn "sudo update-ca-certificates failed"
    log "Installed local CA into system trust store (sudo)"
    return 0
  fi

  warn "Skipping system trust store install (needs root/sudo without password prompt)"
}

if ! command -v mkcert >/dev/null 2>&1; then
  log "mkcert is not installed. Skipping trusted localhost certificate setup."
  log "Install mkcert to enable trusted HTTPS in Chrome/Firefox."
  exit 0
fi

mkdir -p "${CERT_DIR}"

# Install local CA if needed. Non-fatal on environments where store updates are restricted.
mkcert -install >/dev/null 2>&1 || true

CA_FILE="$(mkcert -CAROOT)/rootCA.pem"
if [[ ! -f "$CA_FILE" ]]; then
  warn "mkcert CA file not found at ${CA_FILE}; skipping trust store import"
else
  ensure_certutil || true

  # Chrome/Chromium on Linux uses NSS DB in ~/.pki/nssdb.
  mkdir -p "$HOME/.pki/nssdb"
  import_ca_to_nss_db "$HOME/.pki/nssdb" "$CA_FILE"

  # Firefox uses per-profile NSS DBs.
  import_ca_to_firefox_profiles "$CA_FILE"

  # Optional system trust (best effort, may require elevated privileges).
  install_ca_to_system_store "$CA_FILE"
fi

log "Generating localhost certificate with mkcert..."
mkcert \
  -cert-file "${CERT_FILE}" \
  -key-file "${KEY_FILE}" \
  localhost 127.0.0.1 ::1 >/dev/null

# Ensure target namespace exists before creating/updating secret.
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl apply -f k8s/namespace.yaml >/dev/null

log "Creating/updating TLS secret ${SECRET_NAME} in namespace ${NAMESPACE}..."
kubectl -n "${NAMESPACE}" create secret tls "${SECRET_NAME}" \
  --cert="${CERT_FILE}" \
  --key="${KEY_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

log "TLS secret ready: ${NAMESPACE}/${SECRET_NAME}"
