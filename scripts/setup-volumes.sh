#!/bin/bash
# =============================================================================
# Setup script for K8s Moodle Stack — Initialize host volume mounts
# =============================================================================
# This script prepares the host machine for running Moodle in Kubernetes.
# It creates directories for volume mounts and optionally clones Moodle source.
#
# Usage:
#   ./scripts/setup-volumes.sh
#
# What it does:
#   1. Creates /moodle38, /moodle45, /moodle52 directories (or custom paths)
#   2. Initializes each with a shallow git clone of the Moodle repository
#   3. Sets proper permissions for the kubernetes user/minikube
#   4. Provides instructions for mounting volumes in minikube (if needed)
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Volume mount directories (can be overridden with environment variables)
MOODLE38_DIR="${MOODLE38_DIR:-${PROJECT_ROOT}/moodlefiles/moodle38}"
MOODLE45_DIR="${MOODLE45_DIR:-${PROJECT_ROOT}/moodlefiles/moodle45}"
MOODLE52_DIR="${MOODLE52_DIR:-${PROJECT_ROOT}/moodlefiles/moodle52}"

# Host paths used by Kubernetes hostPath mounts
MOODLE38_HOST="${MOODLE38_HOST:-/moodle38}"
MOODLE45_HOST="${MOODLE45_HOST:-/moodle45}"
MOODLE52_HOST="${MOODLE52_HOST:-/moodle52}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Create and initialize a Moodle volume directory
setup_moodle_volume() {
    local volume_dir="$1"
    local branch="$2"
    local version="$3"

    log_info "Setting up Moodle $version in $volume_dir ..."

    # Create directory if it doesn't exist
    if [ ! -d "$volume_dir" ]; then
        log_info "Creating directory: $volume_dir"
        if ! mkdir -p "$volume_dir"; then
            log_error "Failed to create directory: $volume_dir"
            return 1
        fi
    else
        log_info "Directory already exists: $volume_dir"
    fi

    # Check if Moodle is already cloned (use config-dist.php as it exists in all versions)
    if [ -f "$volume_dir/config-dist.php" ]; then
        log_success "Moodle $version already cloned at $volume_dir"
    else
        log_info "Cloning Moodle $version ($branch) into $volume_dir ..."
        if git clone --depth=1 --branch "$branch" \
            https://github.com/moodle/moodle.git "$volume_dir" 2>/dev/null; then
            log_success "Moodle $version cloned successfully"
        else
            log_error "Failed to clone Moodle $version"
            return 1
        fi
    fi

    # Keep install flow consistent across all Moodle versions.
    # config.php must be managed by the container's persisted config volume,
    # not by local source files.
    if [ -f "$volume_dir/config.php" ]; then
        log_warning "Removing stale local config.php from $volume_dir"
        rm -f "$volume_dir/config.php"
    fi

    # Set proper permissions
    log_info "Setting permissions on $volume_dir ..."
    if [ -d "$volume_dir" ]; then
        chmod 755 "$volume_dir"
        # Make it world-readable so minikube can access it
        find "$volume_dir" -type d -exec chmod 755 {} + 2>/dev/null || true
        find "$volume_dir" -type f -exec chmod 644 {} + 2>/dev/null || true
        log_success "Permissions set on $volume_dir"
    fi
}

# Check if minikube is running
check_minikube() {
    log_info "Checking minikube status..."
    if command -v minikube &> /dev/null; then
        if minikube status &> /dev/null; then
            log_success "minikube is running"
            return 0
        else
            log_warning "minikube is installed but not running"
            log_info "Start minikube with: minikube start"
            return 1
        fi
    else
        log_warning "minikube is not installed"
        log_info "Install minikube: https://minikube.sigs.k8s.io/docs/start/"
        return 1
    fi
}

# Check if git is available
check_git() {
    if ! command -v git &> /dev/null; then
        log_error "git is not installed. Please install git to continue."
        exit 1
    fi
    log_success "git is available"
}

# Start a minikube mount in the background if it is not already running
start_minikube_mount() {
    local src="$1"
    local dest="$2"
    local log_file="${PROJECT_ROOT}/.minikube-mount-${dest//\//_}.log"

    if pgrep -f "minikube mount ${src}:${dest}" >/dev/null 2>&1; then
        log_info "Minikube mount already running for ${src} -> ${dest}"
        return 0
    fi

    log_info "Mounting ${src} into minikube at ${dest} ..."
    nohup minikube mount "${src}:${dest}" > "${log_file}" 2>&1 &
    sleep 1

    if pgrep -f "minikube mount ${src}:${dest}" >/dev/null 2>&1; then
        log_success "Started minikube mount for ${dest} (log: ${log_file})"
    else
        log_warning "Failed to start minikube mount for ${dest}. Check ${log_file}"
    fi
}

# Create persistent volume directories on minikube for config and data
setup_minikube_persistent_volumes() {
    log_info "Setting up persistent volume directories on minikube..."

    if ! command -v minikube >/dev/null 2>&1; then
        log_error "minikube is not installed; cannot create persistent volume directories."
        return 1
    fi

    if ! minikube status >/dev/null 2>&1; then
        log_error "minikube is not running. Start it with: minikube start"
        return 1
    fi

    log_info "Creating /mnt/moodle-volumes/ directories on minikube..."
    
    # Create all required directories
    local dirs=(
        "/mnt/moodle-volumes/mysql-data"
        "/mnt/moodle-volumes/postgres-data"
        "/mnt/moodle-volumes/redis-data"
        "/mnt/moodle-volumes/pgadmin-data"
        "/mnt/moodle-volumes/moodle38-config"
        "/mnt/moodle-volumes/moodle38-data"
        "/mnt/moodle-volumes/moodle45-config"
        "/mnt/moodle-volumes/moodle45-data"
        "/mnt/moodle-volumes/moodle52-config"
        "/mnt/moodle-volumes/moodle52-data"
    )
    
    for dir in "${dirs[@]}"; do
        log_info "Creating: $dir"
        if ! minikube ssh "sudo mkdir -p '$dir' && sudo chmod 777 '$dir'" 2>/dev/null; then
            log_error "Failed to create $dir on minikube"
            return 1
        fi
    done
    
    log_success "Persistent volume directories created on minikube"
}

# Setup minikube mounts for local Moodle source directories
setup_minikube_mounts() {
    log_info "Checking minikube mount requirements..."

    local driver
    driver=$(minikube config get driver 2>/dev/null || echo "")
    log_info "minikube driver: ${driver:-unknown}"

    if ! command -v minikube >/dev/null 2>&1; then
        log_warning "minikube is not installed; cannot mount local source directories."
        return 1
    fi

    if ! minikube status >/dev/null 2>&1; then
        log_warning "minikube is not running; mount commands cannot be started."
        return 1
    fi

    log_info "Mounting local Moodle source directories into minikube host paths..."
    start_minikube_mount "${MOODLE38_DIR}" "${MOODLE38_HOST}"
    start_minikube_mount "${MOODLE45_DIR}" "${MOODLE45_HOST}"
    start_minikube_mount "${MOODLE52_DIR}" "${MOODLE52_HOST}"
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    log_info "=============================================================="
    log_info "Moodle K8s Stack — Volume Setup"
    log_info "=============================================================="
    log_info ""

    # Check prerequisites
    log_info "Checking prerequisites..."
    check_git

    # Optionally warn about minikube (but don't fail)
    check_minikube || true

    log_info ""
    log_info "Setting up volume mounts..."
    log_info ""

    # Setup each Moodle version volume
    setup_moodle_volume "$MOODLE38_DIR" "MOODLE_38_STABLE" "3.8" || exit 1
    log_info ""

    setup_moodle_volume "$MOODLE45_DIR" "MOODLE_405_STABLE" "4.5" || exit 1
    log_info ""

    setup_moodle_volume "$MOODLE52_DIR" "MOODLE_502_STABLE" "5.2" || exit 1
    log_info ""

    # Create persistent volume directories on minikube for config and data
    setup_minikube_persistent_volumes || exit 1
    log_info ""

    # NOTE: The Moodle source is no longer mounted into minikube over 9p.
    # It is baked into each image at build time and hot-reloaded by Tilt's
    # live_update (see Tiltfile). The 9p mount was extremely slow for Moodle's
    # tens of thousands of small files and made the CLI installer crawl.
    # setup_minikube_mounts is intentionally left unused; kill any stale
    # `minikube mount .../moodlefiles/...` processes from a previous setup.
    if pgrep -f "minikube mount .*moodlefiles" >/dev/null 2>&1; then
        log_warning "Stale 'minikube mount' (9p) processes detected — these are no longer needed."
        log_info "Stop them with: pkill -f 'minikube mount .*moodlefiles'"
    fi

    log_info ""
    log_success "=============================================================="
    log_success "Setup complete!"
    log_success "=============================================================="
    log_info ""
    log_info "Next steps:"
    log_info "  1. Ensure minikube is running:"
    log_info "     minikube start"
    log_info ""
    log_info "  2. (No 'minikube mount' needed — source is baked into the image"
    log_info "      and hot-reloaded by Tilt live_update. Stop any old mounts:"
    log_info "      pkill -f 'minikube mount .*moodlefiles')"
    log_info ""
    log_info "  3. Start Tilt:"
    log_info "     tilt up"
    log_info ""
    log_info "  4. Open Tilt UI (automatically opens) or navigate to:"
    log_info "     http://localhost:10350"
    log_info ""
    log_info "  5. Manually trigger Moodle instances from the Tilt UI ▶"
    log_info ""
}

main "$@"
