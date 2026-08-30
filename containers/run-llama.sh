#!/usr/bin/env bash
# =============================================================================
# llama.cpp Container Runner
#
# Usage:
#   ./run-llama.sh --gpu 12.9 --model /path/to/model.gguf [--port 9696]
#   ./run-llama.sh --gpu 13.2 --model /path/to/model.gguf --port 9698
#   ./run-llama.sh --config containers/configs/my-model.json
#   ./run-llama.sh --router --model-a /path/model-a.gguf --model-b /path/model-b.gguf
#   ./run-llama.sh --stop --gpu all
#   ./run-llama.sh --status
#   ./run-llama.sh --build
#
# GPU options: 12.9 | 13.2 | all
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../..")"
IMAGES_DIR="$SCRIPT_DIR/images"
PARSER="$SCRIPT_DIR/parser.py"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
GPU=""
MODEL=""
MODEL_A=""
MODEL_B=""
PORT=""
PORT_A=""
PORT_B=""
N_GPU_LAYERS=""
MODEL_A_TAG="default"
MODEL_B_TAG="default"
CONFIG=""
ACTION=""       # build | status | stop | router
ROUTER_BACKEND=false

# ---------------------------------------------------------------------------
# GPU configs
# ---------------------------------------------------------------------------
declare -A GPU_PORT=( [12.9]=9696 [13.2]=9698 )
declare -A GPU_IMAGE=( [12.9]="llama-server:cuda12.9" [13.2]="llama-server:cuda13.2" )
declare -A GPU_NAME=( [12.9]="gtx1060" [13.2]="rtx3050" )
declare -A GPU_CONTAINER=( [12.9]="llama-cpp-12.9" [13.2]="llama-cpp-13.2" )
declare -A GPU_CF=( [12.9]="cuda-12-9.Containerfile" [13.2]="cuda-13-2.Containerfile" )

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpu)
            GPU="$2"; shift 2 ;;
        --model)
            MODEL="$2"; shift 2 ;;
        --model-a)
            MODEL_A="$2"; shift 2 ;;
        --model-b)
            MODEL_B="$2"; shift 2 ;;
        --model-a-tag)
            MODEL_A_TAG="$2"; shift 2 ;;
        --model-b-tag)
            MODEL_B_TAG="$2"; shift 2 ;;
        --port)
            PORT="$2"; shift 2 ;;
        --port-a)
            PORT_A="$2"; shift 2 ;;
        --port-b)
            PORT_B="$2"; shift 2 ;;
        --n-gpu-layers)
            N_GPU_LAYERS="$2"; shift 2 ;;
        --config)
            CONFIG="$2"; shift 2 ;;
        --router)
            ACTION="router"; shift ;;
        --router-backend)
            ROUTER_BACKEND=true; shift ;;
        --stop)
            ACTION="stop"; shift ;;
        --status)
            ACTION="status"; shift ;;
        --build)
            ACTION="build"; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "GPU options: 12.9 | 13.2 | all"
            echo ""
            echo "Commands:"
            echo "  --gpu <ver> --model <path>  Run a single server"
            echo "  --config <json>             Run from a JSON config file"
            echo "  --router --model-a <path> --model-b <path>  Run router mode"
            echo "  --router-backend             Mark this instance as a router backend"
            echo "  --stop --gpu <ver|all>       Stop container(s)"
            echo "  --status                     Show running containers"
            echo "  --build                      Build all images"
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[run-llama] $(date '+%H:%M:%S') $*"; }

get_port() {
    local gpu="$1"
    if [[ -n "$PORT" ]]; then
        echo "$PORT"
    else
        echo "${GPU_PORT[$gpu]}"
    fi
}

get_image() {
    local gpu="$1"
    echo "${GPU_IMAGE[$gpu]}"
}

get_container_name() {
    local gpu="$1"
    echo "${GPU_CONTAINER[$gpu]}"
}

# ---------------------------------------------------------------------------
# Config-driven run
# ---------------------------------------------------------------------------
do_run_from_config() {
    if [[ ! -f "$CONFIG" ]]; then
        echo "Error: Config file not found: $CONFIG" >&2
        exit 1
    fi

    if [[ ! -x "$PARSER" ]]; then
        echo "Error: Parser not found at $PARSER" >&2
        exit 1
    fi

    log "Parsing config: $CONFIG"

    # The parser outputs a single line of llama-server args
    local cli_args
    cli_args=$(python3 "$PARSER" "$CONFIG")

    # Extract GPU version, port, and model from the config
    local gpu_version port model_path
    gpu_version=$(python3 -c "import json; c=json.load(open('$CONFIG')); print(c.get('cuda_version','12.9'))")
    port=$(python3 -c "import json; c=json.load(open('$CONFIG')); print(c.get('port', ${GPU_PORT[$gpu_version]}))")
    model_path=$(python3 -c "import json; c=json.load(open('$CONFIG')); print(c.get('model_path',''))")

    if [[ -z "$model_path" ]]; then
        echo "Error: model_path not specified in config: $CONFIG" >&2
        exit 1
    fi

    local image name
    image=$(get_image "$gpu_version")
    name=$(get_container_name "$gpu_version")

    # Stop existing container if running
    if podman ps -q --filter "name=$name" 2>/dev/null | grep -q .; then
        log "Stopping existing $name..."
        podman stop "$name" 2>/dev/null || true
        podman rm "$name" 2>/dev/null || true
    fi

    # Check image exists
    if ! podman images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "^${image}$"; then
        echo "Error: Image $image not found. Run with --build first." >&2
        exit 1
    fi

    local run_args=(
        --rm -d
        --name "$name"
        --device nvidia.com/gpu=all
        --security-opt=label=disable
        --network agentx-network
        -p "${port}:9696"
        -v "$(dirname "${model_path}"):/models:ro,z"
    )

    local server_args=(
        "$image"
        $cli_args
    )

    log "Starting $name -> :$port (model: $model_path)"
    podman run "${run_args[@]}" "${server_args[@]}"
    log "Container $name started."
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
do_build() {
    log "Building llama.cpp containers..."

    for ver in 12.9 13.2; do
        local cf="${GPU_CF[$ver]}"
        local img="${GPU_IMAGE[$ver]}"
        log "Building $img from $cf..."
        podman build -t "$img" -f "$IMAGES_DIR/$cf" "$SCRIPT_DIR"
    done

    log "Build complete."
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
do_status() {
    log "Container status:"
    podman ps --filter "name=llama-cpp-" --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Stop
# ---------------------------------------------------------------------------
do_stop() {
    if [[ "$GPU" == "all" ]]; then
        log "Stopping all llama.cpp containers..."
        for ver in 12.9 13.2; do
            local name
            name=$(get_container_name "$ver")
            if podman ps -q --filter "name=$name" 2>/dev/null | grep -q .; then
                podman stop "$name" && log "Stopped $name"
            else
                log "$name not running"
            fi
        done
    else
        local name
        name=$(get_container_name "$GPU")
        if podman ps -q --filter "name=$name" 2>/dev/null | grep -q .; then
            podman stop "$name" && log "Stopped $name"
        else
            log "$name not running"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Run single server
# ---------------------------------------------------------------------------
do_run_single() {
    if [[ -z "$GPU" ]]; then
        echo "Error: --gpu is required for single mode." >&2
        exit 1
    fi
    if [[ -z "$MODEL" ]]; then
        echo "Error: --model is required for single mode." >&2
        exit 1
    fi

    local image port name
    image=$(get_image "$GPU")
    port=$(get_port "$GPU")
    name=$(get_container_name "$GPU")

    # Stop existing container if running
    if podman ps -q --filter "name=$name" 2>/dev/null | grep -q .; then
        log "Stopping existing $name..."
        podman stop "$name" 2>/dev/null || true
        podman rm "$name" 2>/dev/null || true
    fi

    # Check image exists
    if ! podman images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "^${image}$"; then
        echo "Error: Image $image not found. Run with --build first." >&2
        exit 1
    fi

    local model_basename
    model_basename=$(basename "$MODEL")

    local run_args=(
        --rm -d
        --name "$name"
        --device nvidia.com/gpu=all
        --security-opt=label=disable
        --network agentx-network
        -p "${port}:9696"
        -v "$(dirname "${MODEL}"):/models:ro,z"
    )

    local server_args=(
        "$image"
        --model "/models/${model_basename}"
    )

    if [[ -n "$N_GPU_LAYERS" ]]; then
        server_args+=(--n-gpu-layers "$N_GPU_LAYERS")
    fi

    log "Starting $name -> :$port (model: $MODEL)"
    podman run "${run_args[@]}" "${server_args[@]}"
    log "Container $name started."
}

# ---------------------------------------------------------------------------
# Run router mode
# ---------------------------------------------------------------------------
do_run_router() {
    if [[ -z "$MODEL_A" || -z "$MODEL_B" ]]; then
        echo "Error: --model-a and --model-b are required for router mode." >&2
        exit 1
    fi

    # Default ports if not specified
    [[ -z "$PORT_A" ]] && PORT_A=9697
    [[ -z "$PORT_B" ]] && PORT_B=9698

    # Stop existing backend containers
    for ver in 12.9 13.2; do
        local name
        name=$(get_container_name "$ver")
        if podman ps -q --filter "name=$name" 2>/dev/null | grep -q .; then
            podman stop "$name" 2>/dev/null || true
            podman rm "$name" 2>/dev/null || true
        fi
    done

    # Check images exist
    for ver in 12.9 13.2; do
        local image
        image=$(get_image "$ver")
        if ! podman images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "^${image}$"; then
            echo "Error: Image $image not found. Run with --build first." >&2
            exit 1
        fi
    done

    # Start router FIRST so backends can resolve its hostname
    log "Starting router -> :9696"
    podman run --rm -d \
        --name llama-router \
        --network agentx-network \
        -p 9696:9696 \
        "$(get_image 12.9)" \
        --router \
        --router-backend "http://llama-cpp-12.9:9696 $MODEL_A_TAG" \
        --router-backend "http://llama-cpp-13.2:9696 $MODEL_B_TAG"

    # Wait for router to be ready
    sleep 2

    local model_a_basename model_b_basename
    model_a_basename=$(basename "$MODEL_A")
    model_b_basename=$(basename "$MODEL_B")

    # Backend 1 (12.9 / GTX 1060)
    log "Starting backend 1 (llama-cpp-12.9) -> :$PORT_A"
    podman run --rm -d \
        --name llama-cpp-12.9 \
        --device nvidia.com/gpu=all \
        --security-opt=label=disable \
        --network agentx-network \
        -p "${PORT_A}:9696" \
        -v "$(dirname "${MODEL_A}"):/models:ro,z" \
        "$(get_image 12.9)" \
        --model "/models/${model_a_basename}" \
        --router-url "http://llama-router:9696" \
        --router-tag "$MODEL_A_TAG"

    # Backend 2 (13.2 / RTX 3050)
    log "Starting backend 2 (llama-cpp-13.2) -> :$PORT_B"
    podman run --rm -d \
        --name llama-cpp-13.2 \
        --device nvidia.com/gpu=all \
        --security-opt=label=disable \
        --network agentx-network \
        -p "${PORT_B}:9696" \
        -v "$(dirname "${MODEL_B}"):/models:ro,z" \
        "$(get_image 13.2)" \
        --model "/models/${model_b_basename}" \
        --router-url "http://llama-router:9696" \
        --router-tag "$MODEL_B_TAG"

    log "Router mode started. Backend 1 ($MODEL_A_TAG) -> :$PORT_A, Backend 2 ($MODEL_B_TAG) -> :$PORT_B, Router -> :9696"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ -n "$CONFIG" ]]; then
    do_run_from_config
elif [[ -n "$ACTION" ]]; then
    case "$ACTION" in
        build)   do_build ;;
        status)  do_status ;;
        stop)    do_stop ;;
        router)  do_run_router ;;
        *)       echo "Unknown action: $ACTION" >&2; exit 1 ;;
    esac
else
    if [[ -n "$GPU" && -n "$MODEL" ]]; then
        do_run_single
    else
        echo "Error: No action specified. Use --help for usage." >&2
        exit 1
    fi
fi
