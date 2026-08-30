# =============================================================================
# Justfile — Unified Build & Container Manager
#
# WSL2/Windows: All commands run in WSL2 terminal.
#   Windows paths are accessed via /mnt/<drive>/...
#
# Native Linux: Commands run directly on the host.
#
# Prerequisites:
#   - Podman installed (WSL2 or native Linux)
#   - NVIDIA drivers installed (Windows 11 22H2+ or Linux driver)
#   - $LLAMA_MODELS_PATH set in ~/.bashrc (WSL2/Windows)
#   - Podman network: podman network create agentx-network
#
# GPU Mapping:
#   GTX 1060 (compute 6.1) → llama-server:cuda12.9
#   RTX 3050 (compute 8.6) → llama-server:cuda13.2
# =============================================================================

# ---------------------------------------------------------------------------
# Shared configuration
# ---------------------------------------------------------------------------
# Project root is the directory containing this justfile
project_root := `pwd`

# Container paths
CONTAINERS_DIR := 'containers'
IMAGES_DIR := 'containers/images'
CONFIGS_DIR := 'containers/configs'
PARSER := 'containers/parser.py'
RUNNER := 'containers/run-llama.sh'

# Source build paths
SOURCE_BUILD_DIR := 'source-build'
BUILD_SCRIPTS := 'source-build/scripts'

# WSL2 CUDA architecture defaults (from config/build.env)
CUDA_ARCH_12_9 := '6.1'
CUDA_ARCH_13_2 := '8.6'

# Image names
IMAGE_12_9 := 'llama-server:cuda12.9'
IMAGE_13_2 := 'llama-server:cuda13.2'

# Container names
CONTAINER_12_9 := 'llama-cpp-12.9'
CONTAINER_13_2 := 'llama-cpp-13.2'
CONTAINER_ROUTER := 'llama-router'

# Podman network
NETWORK := 'agentx-network'

# Port defaults
PORT_12_9 := '9696'
PORT_13_2 := '9698'

# Host bind address
HOST := '0.0.0.0'

# ---------------------------------------------------------------------------
# Recipes
# ---------------------------------------------------------------------------

# =============================================================================
# UPDATE — Pull latest llama.cpp source and update submodule
# =============================================================================

# Pull latest main branch from llama.cpp upstream and update submodule
# Usage: just update
#        just update_branch <branch-or-tag>
update:
	@echo "Updating llama.cpp submodule to latest main..."
	@cd source-build/llama.cpp && git fetch origin master && git checkout master && git pull origin master
	@git add source-build/llama.cpp
	@git commit -m "chore: update llama.cpp submodule to latest" || echo "No changes to commit"
	@echo "Done. Current commit:"
	@git -C source-build/llama.cpp log --oneline -1

# Pull a specific branch or tag from llama.cpp upstream and update submodule
# Usage: just update_branch <branch-or-tag>
update_branch branch_or_tag:
	@echo "Updating llama.cpp submodule to: {{branch_or_tag}}"
	@cd source-build/llama.cpp && git fetch origin {{branch_or_tag}} && git checkout {{branch_or_tag}}
	@git add source-build/llama.cpp
	@git commit -m "chore: update llama.cpp submodule to {{branch_or_tag}}" || echo "No changes to commit"
	@echo "Done. Current commit:"
	@git -C source-build/llama.cpp log --oneline -1

# =============================================================================
# BUILD — Native source builds (llama.cpp compiled from source)
# =============================================================================

# Build llama.cpp from source (CUDA 12.9 — GTX 1060)
# Usage: just build_12_9
build_12_9:
	@echo "Building llama.cpp for CUDA 12.9 (GTX 1060, arch {{CUDA_ARCH_12_9}})..."
	@bash '{{BUILD_SCRIPTS}}/build.sh' 12.9

# Build llama.cpp from source (CUDA 13.2 — RTX 3050)
# Usage: just build_13_2
build_13_2:
	@echo "Building llama.cpp for CUDA 13.2 (RTX 3050, arch {{CUDA_ARCH_13_2}})..."
	@bash '{{BUILD_SCRIPTS}}/build.sh' 13.2

# Build llama.cpp from source (both CUDA versions)
# Usage: just build-all
build-all:
	@echo "Building llama.cpp for all CUDA versions..."
	@bash '{{BUILD_SCRIPTS}}/build.sh' 12.9
	@bash '{{BUILD_SCRIPTS}}/build.sh' 13.2

# Build llama.cpp from source on Windows (PowerShell) — CUDA 12.9
# Usage: just build_windows_12_9
# Note: Run from Windows PowerShell, not WSL2
build_windows_12_9:
	@echo "Building llama.cpp for CUDA 12.9 (Windows/PowerShell)..."
	powershell -ExecutionPolicy Bypass -File '{{BUILD_SCRIPTS}}/build.ps1'

# Build llama.cpp from source on Windows (PowerShell) — CUDA 13.2
# Usage: just build_windows_13_2
# Note: Run from Windows PowerShell, not WSL2
build_windows_13_2:
	@echo "Building llama.cpp for CUDA 13.2 (Windows/PowerShell)..."
	powershell -ExecutionPolicy Bypass -File '{{BUILD_SCRIPTS}}/build.ps1'

# =============================================================================
# CONTAINER — Container image management
# =============================================================================

# Build the CUDA 12.9 container image
# Usage: just container_build_12_9
container_build_12_9:
	@echo "Building {{IMAGE_12_9}} from {{IMAGES_DIR}}/cuda-12-9.Containerfile..."
	@podman build -t {{IMAGE_12_9}} -f '{{IMAGES_DIR}}/cuda-12-9.Containerfile' '{{CONTAINERS_DIR}}'

# Build the CUDA 13.2 container image
# Usage: just container_build_13_2
container_build_13_2:
	@echo "Building {{IMAGE_13_2}} from {{IMAGES_DIR}}/cuda-13-2.Containerfile..."
	@podman build -t {{IMAGE_13_2}} -f '{{IMAGES_DIR}}/cuda-13-2.Containerfile' '{{CONTAINERS_DIR}}'

# Build all container images
# Usage: just container_build_all
container_build_all:
	@echo "Building all container images..."
	@just container_build_12_9
	@just container_build_13_2

# List container images
# Usage: just container_list
container_list:
	@echo "Container images:"
	@podman images --format "table {{ '{{' }}.Repository{{ '}}' }}\t{{ '{{' }}.Tag{{ '}}' }}\t{{ '{{' }}.Size{{ '}}' }}\t{{ '{{' }}.CreatedSince{{ '}}' }}" | grep llama-server

# ============================================================================
# RUN — Container execution
# ============================================================================

# Run a single container (CUDA 12.9) with a model
# Usage: just run_12_9 --model /mnt/f/models/my-model.gguf
#          just run_12_9 --model /mnt/f/models/my-model.gguf --port 9696
run_12_9 args:
	@bash '{{RUNNER}}' --gpu 12.9 {{args}}

# Run a single container (CUDA 13.2) with a model
# Usage: just run_13_2 --model /mnt/f/models/my-model.gguf
#          just run_13_2 --model /mnt/f/models/my-model.gguf --port 9698
run_13_2 args:
	@bash '{{RUNNER}}' --gpu 13.2 {{args}}

# Run using a JSON config file
# Usage: just run_config --config containers/configs/my-model.json
run_config args:
	@bash '{{RUNNER}}' {{args}}

# Run a single container (specify GPU version via --gpu flag)
# Usage: just run --gpu 12.9 --model /mnt/f/models/model.gguf
#          just run --gpu 13.2 --model /mnt/f/models/model.gguf --port 9698
run args:
	@bash '{{RUNNER}}' {{args}}

# Run router mode with two backend containers
# Usage: just run_router --model-a /mnt/f/models/model-a.gguf --model-b /mnt/f/models/model-b.gguf
run_router args:
	@bash '{{RUNNER}}' --router {{args}}

# ============================================================================
# STATUS — Container status management
# ============================================================================

# Show status of all llama.cpp containers
# Usage: just status
status:
	@bash '{{RUNNER}}' --status

# Stop all llama.cpp containers
# Usage: just stop
stop:
	@bash '{{RUNNER}}' --stop --gpu all

# Stop a specific container
# Usage: just stop_12_9
#          just stop_13_2
stop_12_9:
	@bash '{{RUNNER}}' --stop --gpu 12.9

stop_13_2:
	@bash '{{RUNNER}}' --stop --gpu 13.2

# ============================================================================
# CONFIG — Config file operations
# ============================================================================

# Parse a JSON config and show the generated llama-server CLI args (dry run)
# Usage: just config_show containers/configs/my-model.json
config_show config_path:
	@echo "Parsing config: {{config_path}}"
	@echo "Generated CLI:"
	@python3 '{{PARSER}}' '{{config_path}}'
	@echo ""

# Validate a JSON config file
# Usage: just config_validate containers/configs/my-model.json
config_validate config_path:
	@echo "Validating config: {{config_path}}"
	@python3 -c "import json; config = json.load(open('{{config_path}}')); print('Config keys:', ', '.join(k for k in config.keys() if not k.startswith('_'))); print('Model:', config.get('model', 'N/A')); print('CUDA version:', config.get('cuda_version', 'N/A')); print('Valid JSON OK')"

# List all available model configs
# Usage: just config_list
config_list:
	@echo "Available model configs:"
	@python3 -c "import json,os; [print(' ',os.path.splitext(f)[0],'(CUDA',json.load(open(os.path.join('{{CONFIGS_DIR}}',f))).get('cuda_version','?'),')') for f in sorted(os.listdir('{{CONFIGS_DIR}}')) if f.endswith('.json')]"

# ============================================================================
# CLEAN — Cleanup operations
# ============================================================================

# Clean native build artifacts (Linux/WSL2)
# Usage: just clean_native
clean_native:
	@echo "Cleaning native build artifacts..."
	@bash '{{BUILD_SCRIPTS}}/clean.sh' --native

# Clean native build artifacts (Windows/PowerShell)
# Usage: just clean_native_windows
# Note: Run from Windows PowerShell, not WSL2
clean_native_windows:
	@echo "Cleaning native build artifacts (Windows)..."
	powershell -ExecutionPolicy Bypass -File '{{BUILD_SCRIPTS}}/clean.ps1' --native

# Clean WSL2 build artifacts
# Usage: just clean_wsl2
clean_wsl2:
	@echo "Cleaning WSL2 build artifacts..."
	@bash '{{BUILD_SCRIPTS}}/clean.sh' --wsl2

# Clean all artifacts (native + WSL2)
# Usage: just clean_all
clean_all:
	@echo "Cleaning all build artifacts..."
	@bash '{{BUILD_SCRIPTS}}/clean.sh'

# Clean stopped containers
# Usage: just clean_containers
clean_containers:
	@echo "Removing stopped containers..."
	@podman rm llama-cpp-12.9 llama-cpp-13.2 llama-router 2>/dev/null || true
	@echo "Done."

# ============================================================================
# NVIDIA — NVIDIA Container Toolkit (auto-added to help below)
# ============================================================================

# ============================================================================
# NETWORK — Podman network management
# ============================================================================

# Create the Podman network (required once)
# Usage: just network_create
network_create:
	@echo "Creating Podman network '{{NETWORK}}'..."
	@podman network create {{NETWORK}} 2>/dev/null || echo "Network '{{NETWORK}}' already exists"
	@echo "Done."

# Show network status
# Usage: just network_status
network_status:
	@echo "Podman networks:"
	@podman network ls

# ============================================================================
# NVIDIA — NVIDIA Container Toolkit setup
#   WSL2/Windows: Installs inside Podman Machine
#   Native Linux: Installs directly on host
# ============================================================================

# Initialize Podman Machine if not already created (WSL2/Windows only)
# Usage: just nvidia-init
nvidia-init:
	@bash '{{CONTAINERS_DIR}}/scripts/setup-nvidia-toolkit.sh' --init-only

# Install NVIDIA Container Toolkit
#   WSL2/Windows: Installs inside Podman Machine
#   Native Linux: Installs directly on host (auto-detects platform)
# Usage: just nvidia-toolkit
#        just nvidia-toolkit --force   # Force reinstall
#        just nvidia-toolkit --verify  # Only check status
#        just nvidia-toolkit --platform rhel   # Force RHEL platform
#        just nvidia-toolkit --platform debian # Force Debian/Ubuntu
nvidia-toolkit args:
	@bash '{{CONTAINERS_DIR}}/scripts/setup-nvidia-toolkit.sh' {{args}}

# Verify NVIDIA Container Toolkit installation
# Usage: just nvidia-verify
nvidia-verify:
	@bash '{{CONTAINERS_DIR}}/scripts/setup-nvidia-toolkit.sh' --verify

# Remove NVIDIA Container Toolkit and CDI spec
# Usage: just nvidia-clean
nvidia-clean:
	@bash '{{CONTAINERS_DIR}}/scripts/setup-nvidia-toolkit.sh' --clean

# Test GPU passthrough in a container (shows nvidia-smi output)
# Usage: just nvidia-test
nvidia-test:
	@echo "Testing GPU passthrough in a container..."
	@bash '{{CONTAINERS_DIR}}/scripts/test-gpu.sh'

# ============================================================================
# INFO — Display information
# ============================================================================

# Show GPU and CUDA information
# Usage: just info
info:
	@echo "=== System Info ==="
	@echo "Project root: {{project_root}}"
	@echo ""
	@echo "=== GPU Config ==="
	@echo "GTX 1060 → {{IMAGE_12_9}} (CUDA 12.9, arch {{CUDA_ARCH_12_9}})"
	@echo "RTX 3050 → {{IMAGE_13_2}} (CUDA 13.2, arch {{CUDA_ARCH_13_2}})"
	@echo ""
	@echo "=== Container Names ==="
	@echo "{{CONTAINER_12_9}} → port {{PORT_12_9}}"
	@echo "{{CONTAINER_13_2}} → port {{PORT_13_2}}"
	@echo "{{CONTAINER_ROUTER}} → port 9696"
	@echo ""
	@echo "=== Network ==="
	@echo "{{NETWORK}}"
	@echo ""
	@echo "=== Quick Start ==="
	@echo "1. just network_create    # Create Podman network (one-time)"
	@echo "2. just container_build_all   # Build images"
	@echo "3. just run_config --config {{CONFIGS_DIR}}/qwen-3.6-35B-A3B-coding.json"

# ============================================================================
# HELP — Show usage
# ============================================================================

# Show all available commands
# Usage: just help
help:
	@echo "================================================================"
	@echo "llama.cpp Container Manager — justfile"
	@echo "================================================================"
	@echo ""
	@echo "UPDATE:"
	@echo "  just update              Pull latest main branch from llama.cpp"
	@echo "  just update --branch <x> Pull specific branch/tag from llama.cpp"
	@echo ""
	@echo "BUILD:"
	@echo "  just build_12_9            Build llama.cpp for CUDA 12.9"
	@echo "  just build_13_2            Build llama.cpp for CUDA 13.2"
	@echo "  just build-all             Build both CUDA versions"
	@echo "  just build_windows_12_9    Build llama.cpp for CUDA 12.9 (Windows/PowerShell)"
	@echo "  just build_windows_13_2    Build llama.cpp for CUDA 13.2 (Windows/PowerShell)"
	@echo ""
	@echo "CONTAINER:"
	@echo "  just container_build_12_9  Build CUDA 12.9 image"
	@echo "  just container_build_13_2  Build CUDA 13.2 image"
	@echo "  just container_build_all   Build all images"
	@echo "  just container_list        List images"
	@echo ""
	@echo "RUN:"
	@echo "  just run --gpu 12.9 --model /path/to/model.gguf"
	@echo "  just run --gpu 13.2 --model /path/to/model.gguf --port 9698"
	@echo "  just run_config --config containers/configs/my-model.json"
	@echo "  just run_router --model-a /path/a.gguf --model-b /path/b.gguf"
	@echo "  (GPU passthrough auto-detected: CDI or WSL2 manual mode)"
	@echo ""
	@echo "STATUS:"
	@echo "  just status              Show container status"
	@echo "  just stop                Stop all containers"
	@echo "  just stop_12.9           Stop CUDA 12.9 container"
	@echo "  just stop_13_2           Stop CUDA 13.2 container"
	@echo ""
	@echo "CONFIG:"
	@echo "  just config_show <file>  Parse config (dry run)"
	@echo "  just config_validate <file>  Validate config file"
	@echo "  just config_list         List available configs"
	@echo ""
	@echo "CLEAN:"
	@echo "  just clean_native        Clean native build artifacts"
	@echo "  just clean_wsl2          Clean WSL2 build artifacts"
	@echo "  just clean_native_windows  Clean native build artifacts (Windows)"
	@echo "  just clean_all           Clean all build artifacts"
	@echo "  just clean_containers    Remove stopped containers"
	@echo ""
	@echo "NVIDIA TOOLKIT (auto-detects platform):"
	@echo "  just nvidia-init         Init Podman Machine (WSL2/Windows only)"
	@echo "  just nvidia-toolkit      Install NVIDIA Container Toolkit"
	@echo "  just nvidia-toolkit --force   Force reinstall"
	@echo "  just nvidia-toolkit --verify  Check if already installed"
	@echo "  just nvidia-toolkit --platform rhel|debian  Force platform"
	@echo "  just nvidia-verify       Quick status check"
	@echo "  just nvidia-clean        Remove toolkit and CDI spec"
	@echo "  just nvidia-test         Test GPU passthrough in a container"
	@echo ""
	@echo "NETWORK:"
	@echo "  just network_create      Create Podman network"
	@echo "  just network_status      Show network status"
	@echo ""
	@echo "INFO:"
	@echo "  just info                Show system and config info"
	@echo "  just help                Show this help"
	@echo ""
	@echo "================================================================"
	@echo "Requirements:"
	@echo "  WSL2/Windows: Run in WSL2 terminal, Windows paths: /mnt/f/..."
	@echo "  Native Linux: Run directly on host"
	@echo "  $LLAMA_MODELS_PATH must be set in ~/.bashrc (WSL2/Windows)"
	@echo "  NVIDIA drivers installed (Windows 11 22H2+ or Linux driver)"
	@echo "================================================================"
