#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# agentx Orchestration Engine
#
# Core lifecycle manager for containerized local agentic coding.
# Validated for official upstream ghcr.io llama.cpp releases.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- 1. Environment & Path Anchoring ---
# Optimizing BASH_SOURCE with an explicit array target index
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"

# Load standalone LLM server performance configuration parameters
CONFIG_FILE="${SCRIPT_DIR}/config.env"
if [ -f "${CONFIG_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
else
    echo -e "\033[0;31m[ERROR]\033[0m Configuration missing at ${CONFIG_FILE}!"
    exit 1
fi

# Define container internal targets and project layouts
NETWORK_NAME="agentx-network"
LLAMA_IMAGE="ghcr.io/ggml-org/llama.cpp:server-cuda13"
LLAMA_CONTAINER="llama-cpp-server"
PI_IMAGE="pi-agent"
PI_CONTAINER="pi-coding-agent"

# Set the operational context workspace (default to host pwd)
WORKSPACE_DIR="${1:-$(pwd)}"
WORKSPACE_DIR="$(cd "${WORKSPACE_DIR}" && pwd)"

PI_CONTAINERFILE="${SCRIPT_DIR}/containers/pi/Containerfile"
PI_CONFIG_DIR="${SCRIPT_DIR}/containers/pi/agent"
HOST_MODELS_DIR="${SCRIPT_DIR}/models"

# Console output formatting strings
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Assert local agent context configuration file is intact
if [ ! -f "${PI_CONTAINERFILE}" ]; then
    error "Missing Pi Agent Containerfile! Verify the 'containers/pi' workspace layout."
fi


# --- 2. Shared Network Infrastructure ---
log "Checking Podman network: ${NETWORK_NAME}..."
if ! podman network exists "${NETWORK_NAME}"; then
    log "Creating podman network: ${NETWORK_NAME}..."
    podman network create "${NETWORK_NAME}"
    success "Network created."
else
    log "Network ${NETWORK_NAME} already exists."
fi


# --- 3. Pull Validation: llama.cpp Server ---
log "Validating availability and freshness of image: ${LLAMA_IMAGE}..."
if ! podman image exists "${LLAMA_IMAGE}"; then
    log "Image '${LLAMA_IMAGE}' not found locally. Pulling from official registry..."
    podman pull "${LLAMA_IMAGE}"
else
    log "Image '${LLAMA_IMAGE}' is available. (Run 'podman pull ${LLAMA_IMAGE}' manually if you want to update)."
fi


# --- 4. Smart Re/Build Validation: Pi Coding Agent ---
log "Validating availability and freshness of image: ${PI_IMAGE}..."
CURRENT_PI_HASH=$(sha256sum "${PI_CONTAINERFILE}" | awk '{print $1}')
REBUILD_PI=false

if podman image exists "${PI_IMAGE}"; then
    EXISTING_PI_HASH=$(podman inspect --format '{{index .Config.Labels "containerfile_hash"}}' "${PI_IMAGE}" 2>/dev/null || echo "")
    
    if [ "${CURRENT_PI_HASH}" != "${EXISTING_PI_HASH}" ]; then
        warn "Changes detected in pi-agent Containerfile. Forcing a rebuild..."
        REBUILD_PI=true
    else
        log "Image '${PI_IMAGE}' is up-to-date. Skipping build layer."
    fi
else
    log "Image '${PI_IMAGE}' not found locally. Initializing initial build..."
    REBUILD_PI=true
fi

if [ "${REBUILD_PI}" = true ]; then
    log "Building ${PI_IMAGE} using: ${PI_CONTAINERFILE}..."
    podman build \
        --label "containerfile_hash=${CURRENT_PI_HASH}" \
        -t "${PI_IMAGE}" \
        -f "${PI_CONTAINERFILE}" \
        "${SCRIPT_DIR}/containers/pi"
    success "${PI_IMAGE} build completed."
fi


# --- 5. Execution Lifecycle: llama.cpp Backend ---
log "Stopping existing ${LLAMA_CONTAINER} if running..."
podman stop "${LLAMA_CONTAINER}" 2>/dev/null || true
podman rm "${LLAMA_CONTAINER}" 2>/dev/null || true

log "Starting ${LLAMA_CONTAINER}..."
if [ ! -d "${HOST_MODELS_DIR}" ]; then
    mkdir -p "${HOST_MODELS_DIR}"
fi

if [ ! -f "${HOST_MODELS_DIR}/${MODEL_FILE}" ]; then
    warn "Model ${MODEL_FILE} not found in ${HOST_MODELS_DIR}."
    warn "Please drop your .gguf file there before continuing."
fi

# Fixed: Explicitly changed target container container name reference and optimized runtime parameters
podman run --rm -d \
    --name "${LLAMA_CONTAINER}" \
    --device nvidia.com/gpu=all \
    --security-opt=label=disable \
    --network "${NETWORK_NAME}" \
    -p "${PORT}:${PORT}" \
    -v "${HOST_MODELS_DIR}":/models:Z \
    "${LLAMA_IMAGE}" \
    --model "/models/${MODEL_FILE}" \
    --host "${HOST}" \
    --port "${PORT}" \
    --n-gpu-layers "${N_GPU_LAYERS}" \
    --n-cpu-moe "${N_CPU_MOE}" \
    --ctx-size "${CTX_SIZE}" \
    --predict "${PREDICT}" \
    --batch-size "${BATCH_SIZE}" \
    --ubatch-size "${UBATCH_SIZE}" \
    --spec-type "${SPEC_TYPE}" \
    --spec-draft-n-max "${SPEC_DRAFT_MAX}" \
    --parallel "${PARALLEL}" \
    --threads "${THREADS}" \
    --temperature "${TEMPERATURE}" \
    --top-p "${TOP_P}" \
    --top-k "${TOP_K}" \
    --min-p "${MIN_P}" \
    --repeat-penalty "${REPEAT_PENALTY}" \
    --presence-penalty "${PRESENCE_PENALTY}" \
    --frequency-penalty "${FREQUENCY_PENALTY}" \
    --reasoning "${REASONING}" \
    --reasoning-budget "${REASONING_BUDGET}" \
    --chat-template-kwargs "${CHAT_KWARGS}" \
    --fit "${FIT}" \
    --flash-attn "${FLASH_ATTN}" \
    --cache-type-k "${CACHE_TYPE_K}" \
    --cache-type-v "${CACHE_TYPE_V}" \
    --split-mode "${SPLIT_MODE}" \
    --no-mmap \
    --jinja


# --- 6. Polling Api Health Check with Early Crash Boundary ---
log "Waiting for LLM server API endpoint to become available..."
MAX_ATTEMPTS=30
ATTEMPT=0
until curl -s "http://localhost:${PORT}/health" >/dev/null 2>&1; do
    # Break early if the container drops out due to OOM or bad architectures
    if ! podman ps --format '{{.Names}}' | grep -q "^${LLAMA_CONTAINER}$"; then
        echo ""
        error "Container '${LLAMA_CONTAINER}' terminated unexpectedly. Run 'podman logs ${LLAMA_CONTAINER}' to debug."
    fi
    
    if [ ${ATTEMPT} -eq ${MAX_ATTEMPTS} ]; then
        echo ""
        error "Timed out waiting for LLM server to reply at http://localhost:${PORT}/health"
    fi

    echo -n "."
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done
echo ""
success "LLM server is healthy!"


# --- 7. Execution Lifecycle: Interactive Pi Coding Agent ---
log "Stopping existing ${PI_CONTAINER} if hanging..."
podman stop "${PI_CONTAINER}" 2>/dev/null || true
podman rm "${PI_CONTAINER}" 2>/dev/null || true

log "Initializing interactive session with ${PI_CONTAINER}..."
log "Target Workspace: ${WORKSPACE_DIR} -> /workspace"
log "Mounting configurations from: ${PI_CONFIG_DIR}"

# Drop into workspace loop with strict rootless sandboxing boundaries
podman run --rm -it \
    --name "${PI_CONTAINER}" \
    --userns=keep-id \
    --network "${NETWORK_NAME}" \
    --read-only \
    --tmpfs /tmp \
    --mount type=tmpfs,destination=/home/pi,tmpfs-mode=0755 \
    -v "${WORKSPACE_DIR}":/workspace:Z \
    -v "${PI_CONFIG_DIR}":/home/pi/.pi/agent:Z \
    "${PI_IMAGE}"
