#!/usr/bin/env bash
# ==============================================================================
# agentx-pi orchestration engine
# ------------------------------------------------------------------------------
# Manages:
#   - deterministic image builds
#   - secure podman runtime lifecycle
#   - reproducible agent workspace execution
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# UI helpers
# ------------------------------------------------------------------------------

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()    { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()     { echo -e "${GREEN}[OK]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ------------------------------------------------------------------------------
# Resolve script directory (robust to symlinks)
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------------------
# Core configuration
# ------------------------------------------------------------------------------

NETWORK_NAME="agentx-network"

IMAGE_NAME="agentx-pi"
CONTAINER_NAME="agentx"

WORKSPACE_DIR="${1:-$(pwd)}"
WORKSPACE_DIR="$(cd "${WORKSPACE_DIR}" && pwd)"

CONTAINERFILE="${SCRIPT_DIR}/container-envs/pi-agent/Containerfile"
AGENT_CONFIG="${SCRIPT_DIR}/container-envs/pi-agent/agent"

# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------

[[ -f "${CONTAINERFILE}" ]] || fail "Missing Containerfile at ${CONTAINERFILE}"
[[ -d "${AGENT_CONFIG}" ]]  || fail "Missing agent config directory"

# ------------------------------------------------------------------------------
# Ensure Podman network exists
# ------------------------------------------------------------------------------

log "Ensuring network: ${NETWORK_NAME}"

if ! podman network exists "${NETWORK_NAME}" 2>/dev/null; then
    podman network create "${NETWORK_NAME}" >/dev/null
    ok "Network created"
else
    ok "Network already exists"
fi

# ------------------------------------------------------------------------------
# Deterministic rebuild logic
# ------------------------------------------------------------------------------

log "Checking image freshness: ${IMAGE_NAME}"

CURRENT_HASH="$(sha256sum "${CONTAINERFILE}" | awk '{print $1}')"

REBUILD=0

if podman image exists "${IMAGE_NAME}"; then
    EXISTING_HASH="$(podman inspect \
        --format '{{ index .Config.Labels "containerfile_hash" }}' \
        "${IMAGE_NAME}" 2>/dev/null || true)"

    if [[ "${CURRENT_HASH}" != "${EXISTING_HASH}" || -z "${EXISTING_HASH}" ]]; then
        warn "Containerfile changed or missing label → rebuild required"
        REBUILD=1
    else
        ok "Image is up-to-date"
    fi
else
    warn "Image not found → build required"
    REBUILD=1
fi

# ------------------------------------------------------------------------------
# Build image
# ------------------------------------------------------------------------------

if [[ "${REBUILD}" -eq 1 ]]; then
    log "Building image: ${IMAGE_NAME}"

    podman build \
        --label "containerfile_hash=${CURRENT_HASH}" \
        -t "${IMAGE_NAME}" \
        -f "${CONTAINERFILE}" \
        "${SCRIPT_DIR}/pi-agent"

    ok "Build complete"
fi

# ------------------------------------------------------------------------------
# Stop existing container (clean restart semantics)
# ------------------------------------------------------------------------------

log "Cleaning up existing container (if any)"

podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# Runtime execution
# ------------------------------------------------------------------------------

log "Starting agent session"
log "Workspace → /workspace"
log "Host      → ${WORKSPACE_DIR}"

# Conservative defaults (override via env if needed)
CPU_LIMIT="${CPU_LIMIT:-4}"
MEM_LIMIT="${MEM_LIMIT:-8g}"

exec podman run --rm -it \
    --name "${CONTAINER_NAME}" \
    --hostname "${IMAGE_NAME}" \
    --userns=keep-id \
    --network "${NETWORK_NAME}" \
    --read-only \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --pids-limit=512 \
    --memory="${MEM_LIMIT}" \
    --cpus="${CPU_LIMIT}" \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=512m \
    --tmpfs /run:rw,nosuid,nodev,size=64m \
    --tmpfs /home/agentx/.npm:rw,nosuid,nodev,size=256m \
    --tmpfs /home/agentx/.cache:rw,nosuid,nodev,size=256m \
    -v "${WORKSPACE_DIR}":/workspace:Z \
    -v "${AGENT_CONFIG}":/home/agentx/.pi/agent:Z \
    "${IMAGE_NAME}"
