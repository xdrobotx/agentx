#!/usr/bin/env bash
# =============================================================================
# llama.cpp — Build from Source (Linux / WSL2)
#
# Usage:
#   ./source-build/scripts/build.sh                  # Build with defaults
#   CUDA_ARCH="61;80;86" ./source-build/scripts/build.sh  # Custom archs
#   INSTALL_DIR="$HOME/ai/llama.cpp" ./source-build/scripts/build.sh  # Custom prefix
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"
SOURCE_BUILD="$PROJECT_ROOT/source-build"
LLAMACPP_SRC="$SOURCE_BUILD/llama.cpp"

# ---------------------------------------------------------------------------
# Config (sourced from shared config)
# ---------------------------------------------------------------------------
source "$SOURCE_BUILD/config/build.env"

# Allow environment overrides
INSTALL_DIR="${INSTALL_DIR_LINUX:-$INSTALL_DIR_LINUX}"
ARTIFACTS_DIR="$SOURCE_BUILD/artifacts"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() { printf "\033[0;36m[agentx build] %s\033[0m\n" "$*"; }
warn() { printf "\033[0;33m[agentx build] WARNING: %s\033[0m\n" "$*"; }

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [[ ! -f "$LLAMACPP_SRC/CMakeLists.txt" ]]; then
    echo "Error: llama.cpp source tree not found at $LLAMACPP_SRC" >&2
    echo "Run 'just update' to initialize submodules." >&2
    exit 1
fi

if ! command -v cmake &>/dev/null; then
    echo "Error: cmake not found. Install cmake first." >&2
    exit 1
fi

if ! command -v make &>/dev/null && ! command -v ninja &>/dev/null; then
    echo "Error: make or ninja not found." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR" "$ARTIFACTS_DIR"

log "Project root : $PROJECT_ROOT"
log "Source       : $LLAMACPP_SRC"
log "Install dir  : $INSTALL_DIR"
log "CUDA archs   : $CUDA_ARCH"
log "Build type   : $BUILD_TYPE"

# ---------------------------------------------------------------------------
# Configure
# ---------------------------------------------------------------------------
cd "$LLAMACPP_SRC"

log "Configuring build..."

cmake -B build \
    -DGGML_CUDA=ON \
    -DGGML_CUDA_BLAS=ON \
    -DGGML_CUDA_BLAS_VENDOR=NVIDIA \
    -DGGML_CUDA_NCCL=ON \
    -DGGML_NATIVE=OFF \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
log "Building (this may take a while)..."

cmake --build build \
    --config "$BUILD_TYPE" \
    --parallel

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
log "Installing to $INSTALL_DIR..."

cmake --install build \
    --config "$BUILD_TYPE"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
if [[ "${KEEP_BUILD_DIR:-false}" != "true" ]]; then
    log "Cleaning build directory..."
    rm -rf build
fi

log "Build complete. Binaries installed to $INSTALL_DIR"
