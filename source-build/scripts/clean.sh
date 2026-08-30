#!/usr/bin/env bash
# =============================================================================
# llama.cpp — Clean Build Artifacts
#
# Usage:
#   ./source-build/scripts/clean.sh              # Clean build + artifacts
#   ./source-build/scripts/clean.sh --native     # Clean only native build dir
#   ./source-build/scripts/clean.sh --wsl2       # Clean only WSL2 build dir
#   ./source-build/scripts/clean.sh --artifacts  # Clean only install artifacts
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"
SOURCE_BUILD="$PROJECT_ROOT/source-build"
LLAMACPP_SRC="$PROJECT_ROOT/llama.cpp"

log() { printf "\033[0;36m[agentx clean] %s\033[0m\n" "$*"; }

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
CLEAN_NATIVE=true
CLEAN_WSL2=false
CLEAN_ARTIFACTS=true

for arg in "$@"; do
    case "$arg" in
        --native)    CLEAN_WSL2=false; CLEAN_ARTIFACTS=false ;;
        --wsl2)      CLEAN_NATIVE=false; CLEAN_ARTIFACTS=false ;;
        --artifacts) CLEAN_NATIVE=false; CLEAN_WSL2=false ;;
        *)           echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Clean native build
# ---------------------------------------------------------------------------
if [[ "$CLEAN_NATIVE" == "true" ]]; then
    if [[ -d "$LLAMACPP_SRC/build" ]]; then
        log "Removing $LLAMACPP_SRC/build..."
        rm -rf "$LLAMACPP_SRC/build"
    else
        log "No native build directory to clean."
    fi
fi

# ---------------------------------------------------------------------------
# Clean WSL2 build (if build.env specifies a WSL2 install dir)
# ---------------------------------------------------------------------------
if [[ "$CLEAN_WSL2" == "true" ]]; then
    source "$PROJECT_ROOT/config/build.env"
    if [[ -d "${INSTALL_DIR_LINUX:-}" ]]; then
        log "Removing WSL2 install: ${INSTALL_DIR_LINUX}"
        rm -rf "${INSTALL_DIR_LINUX}"
    fi
fi

# ---------------------------------------------------------------------------
# Clean artifacts
# ---------------------------------------------------------------------------
if [[ "$CLEAN_ARTIFACTS" == "true" ]]; then
    ARTIFACTS_DIR="$SOURCE_BUILD/artifacts"
    if [[ -d "$ARTIFACTS_DIR" ]]; then
        log "Cleaning artifacts directory..."
        find "$ARTIFACTS_DIR" -mindepth 1 -delete 2>/dev/null || true
    fi
fi

log "Clean complete."
