#!/usr/bin/env bash
# =============================================================================
# Test GPU Passthrough in a Container
#
# Usage:
#   ./test-gpu.sh              # Run with WSL2 manual passthrough
#   ./test-gpu.sh --cdi        # Try CDI mode if available
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[test-gpu] $(date '+%H:%M:%S') $*"; }

# Detect execution method
detect_method() {
    if command -v wsl &>/dev/null; then
        echo "wsl"
    elif command -v podman &>/dev/null && podman machine info &>/dev/null; then
        echo "ssh"
    else
        echo "local"
    fi
}

# Run test with WSL2 manual passthrough
run_wsl2_test() {
    log "Running GPU test with WSL2 manual passthrough..."
    wsl -d podman-machine-default sh -c '
        podman run --rm \
            --device=/dev/dxg \
            -v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro \
            -v /usr/lib/wsl/drivers/nv_dispsi.inf_amd64_671c0a23616db704:/usr/lib/wsl/drivers/nv_dispsi.inf_amd64_671c0a23616db704:ro \
            -e NVIDIA_DRIVER_CAPABILITIES=all \
            -e NVIDIA_VISIBLE_DEVICES=all \
            -e LD_LIBRARY_PATH=/usr/lib/wsl/lib:/usr/lib/wsl/drivers/nv_dispsi.inf_amd64_671c0a23616db704 \
            docker.io/nvidia/cuda:13.3.1-runtime-ubuntu26.04 \
            /usr/lib/wsl/lib/nvidia-smi
    '
}

# Run test with CDI
run_cdi_test() {
    log "Running GPU test with CDI passthrough..."
    podman run --rm --device nvidia.com/gpu=all \
        --security-opt=label=disable \
        docker.io/nvidia/cuda:13.3.1-runtime-ubuntu26.04 \
        nvidia-smi
}

# Main
METHOD=$(detect_method)
log "Execution method: $METHOD"

if [[ "${1:-}" == "--cdi" ]]; then
    run_cdi_test
else
    run_wsl2_test
fi

log "GPU test complete."
