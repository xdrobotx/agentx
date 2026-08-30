#!/usr/bin/env bash
# =============================================================================
# NVIDIA Container Toolkit Setup Script
#
# One-command setup for GPU-accelerated containers with Podman:
#   1. Detects OS (Windows, WSL2, or native Linux)
#   2. Initializes Podman Machine if needed (Windows/WSL2 only)
#   3. Installs NVIDIA Container Toolkit
#   4. Generates CDI spec
#   5. Verifies all checks pass
#
# Usage:
#   ./setup-nvidia-toolkit.sh              # Full install (auto-detects platform)
#   ./setup-nvidia-toolkit.sh --force      # Force reinstall toolkit
#   ./setup-nvidia-toolkit.sh --verify     # Only check status
#   ./setup-nvidia-toolkit.sh --clean      # Remove toolkit and CDI spec
#   ./setup-nvidia-toolkit.sh --init-only  # Only init Podman Machine (Windows/WSL2)
#
# Platform Detection:
#   - Windows (PowerShell/CMD) → Podman Machine (WSL2-backed VM)
#   - WSL2 → Podman Machine (WSL2 distro VM)
#   - Native Linux (RHEL/Fedora) → Direct install on host
#   - Native Linux (Debian/Ubuntu) → Direct install on host
#
# Force Platform (if auto-detection fails):
#   ./setup-nvidia-toolkit.sh --platform rhel
#   ./setup-nvidia-toolkit.sh --platform debian
#
# Prerequisites:
#   - NVIDIA drivers installed (Windows 11 22H2+ or Linux driver)
#   - podman CLI installed
#   - sudo/root access (for toolkit installation)
#
# IMPORTANT:
#   - Windows/WSL2: Toolkit is installed INSIDE the Podman Machine
#   - Native Linux: Toolkit is installed directly on the host system
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
FORCE=false
VERIFY_ONLY=false
CLEAN=false
INIT_ONLY=false
MACHINE_NAME=""
SSH_METHOD=""  # "ssh" or "wsl"
PLATFORM=""   # "rhel", "debian", or empty (auto-detect)
IS_NATIVE_LINUX=false  # true if running on native Linux (no VM)

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)       FORCE=true; shift ;;
        --verify)      VERIFY_ONLY=true; shift ;;
        --clean)       CLEAN=true; shift ;;
        --init-only)   INIT_ONLY=true; shift ;;
        --platform)
            PLATFORM="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force       Force reinstall even if toolkit is detected"
            echo "  --verify      Only check if toolkit is installed (no changes)"
            echo "  --clean       Remove toolkit and CDI spec"
            echo "  --init-only   Only initialize Podman Machine (Windows/WSL2 only)"
            echo "  --platform rhel|debian   Force platform detection"
            echo "  --help        Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log_info()  { echo -e "${BLUE}[setup-toolkit]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[setup-toolkit]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[setup-toolkit]${NC} $*"; }
log_error() { echo -e "${RED}[setup-toolkit]${NC} $*"; }
log_step()  { echo -e "${CYAN}[setup-toolkit]${NC} ▸ $*"; }
log_header(){ echo ""; echo -e "${CYAN}═══════════════════════════════════════════════${NC}"; log_info "$*"; echo -e "${CYAN}═══════════════════════════════════════════════${NC}"; echo ""; }

# ---------------------------------------------------------------------------
# Detect the host OS
# Returns: "windows" or "wsl" or "linux"
# ---------------------------------------------------------------------------
detect_os() {
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        echo "wsl"
    elif [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
        echo "wsl"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    elif command -v powershell &>/dev/null && powershell -c 'Test-Path $env:COMPUTERNAME' &>/dev/null 2>&1; then
        echo "windows"
    elif [[ -d /mnt/c ]] || [[ -d /mnt/d ]]; then
        echo "windows"
    else
        echo "linux"
    fi
}

# ---------------------------------------------------------------------------
# Check if a Podman Machine exists and is running
# ---------------------------------------------------------------------------
machine_exists() {
    local machines
    machines=$(podman machine list --format '{{.Name}}' 2>/dev/null || echo "")
    [[ -n "$machines" ]]
}

# ---------------------------------------------------------------------------
# Check if Podman Machine is running
# ---------------------------------------------------------------------------
machine_running() {
    podman machine info &>/dev/null
}

# ---------------------------------------------------------------------------
# Detect platform for native Linux
# Returns: "rhel", "debian", or "unknown"
# ---------------------------------------------------------------------------
detect_platform() {
    if [[ -n "$PLATFORM" ]]; then
        echo "$PLATFORM"
        return
    fi

    if [[ -f /etc/os-release ]]; then
        local id
        id=$(. /etc/os-release && echo "$ID")
        case "$id" in
            debian|ubuntu|mint) echo "debian" ;;
            rhel|fedora|centos|rocky|almalinux) echo "rhel" ;;
        esac
    fi

    # Fallback: check for package managers
    if command -v dnf &>/dev/null; then
        echo "rhel"
    elif command -v yum &>/dev/null; then
        echo "rhel"
    elif command -v apt-get &>/dev/null; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Initialize Podman Machine (Windows/WSL2 only)
# On native Linux, sets IS_NATIVE_LINUX=true and skips VM init
# ---------------------------------------------------------------------------
init_machine() {
    local os
    os=$(detect_os)

    if [[ "$os" == "windows" ]]; then
        IS_NATIVE_LINUX=false
        MACHINE_NAME="podman-machine-default"
        log_header "Initializing Podman Machine (Windows)"
        log_info "Detected Windows host"
        log_step "Creating Podman Machine (WSL2-backed)..."
        podman machine init --cpus 4 --memory 4096 --disk-size 100 podman-machine-default 2>&1
        log_step "Starting Podman Machine..."
        podman machine start 2>&1

        # Wait for machine to be ready
        log_step "Waiting for Podman Machine to be ready..."
        local retries=30
        while ! machine_running && [[ $retries -gt 0 ]]; do
            sleep 2
            ((retries--))
        done

        if ! machine_running; then
            log_error "Podman Machine failed to start within 60 seconds."
            exit 1
        fi
        log_ok "Podman Machine is running."

    elif [[ "$os" == "wsl" ]]; then
        IS_NATIVE_LINUX=false
        MACHINE_NAME=$(podman machine inspect --format '{{.Name}}' 2>/dev/null | tail -1 || echo "podman-machine-default")

        log_header "Initializing Podman Machine (WSL2)"
        log_info "Detected WSL2 environment"

        # Try to init — might fail if already exists, which is fine
        log_step "Checking for existing Podman Machine..."
        if ! machine_exists; then
            log_info "No Podman Machine found. Attempting to create one..."
            if podman machine init --cpus 4 --memory 4096 --disk-size 100 podman-machine-default 2>&1; then
                log_step "Starting Podman Machine..."
                podman machine start 2>&1
            else
                log_warn "Could not create Podman Machine from WSL2."
                log_info "You may need to run this script from Windows PowerShell/CMD instead."
                log_info "Or manually: podman machine init && podman machine start"
                return 1
            fi
        else
            log_info "Podman Machine already exists: $MACHINE_NAME"
        fi

        # Wait for machine to be ready
        log_step "Waiting for Podman Machine to be ready..."
        local retries=30
        while ! machine_running && [[ $retries -gt 0 ]]; do
            sleep 2
            ((retries--))
        done

        if ! machine_running; then
            log_error "Podman Machine failed to start within 60 seconds."
            exit 1
        fi
        log_ok "Podman Machine is running."

    else
        IS_NATIVE_LINUX=true
        PLATFORM=$(detect_platform)
        log_header "Native Linux Detected"
        log_info "Platform: $PLATFORM"
        log_info "Podman Machine is not needed on native Linux."
        log_info "On Linux, Podman runs directly and the NVIDIA Container"
        log_info "Toolkit is installed directly on the host system."
        return 0
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Detect the best way to execute commands in the Podman Machine
# podman machine ssh works from Windows, but from WSL2 we need wsl -d
# ---------------------------------------------------------------------------
detect_ssh_method() {
    # Get the Podman Machine name
    MACHINE_NAME=$(podman machine inspect --format '{{.Name}}' 2>/dev/null | tail -1 || echo "podman-machine-default")

    # Method 1: wsl -d <name> (works from WSL2 when podman machine ssh fails)
    # We check this FIRST because podman machine ssh is unreliable from WSL2
    if command -v wsl &>/dev/null; then
        if timeout 3 wsl -d "$MACHINE_NAME" sh -c 'echo ssh-ok' &>/dev/null 2>&1; then
            SSH_METHOD="wsl"
            log_info "Using 'wsl -d $MACHINE_NAME' for remote execution (WSL2 detected)"
            return 0
        fi
    fi

    # Method 2: podman machine ssh (works from Windows)
    if timeout 3 podman machine ssh -- echo "ssh-ok" &>/dev/null 2>&1; then
        SSH_METHOD="ssh"
        log_info "Using 'podman machine ssh' for remote execution"
        return 0
    fi

    log_error "Cannot find a way to execute commands in the Podman Machine ($MACHINE_NAME)."
    log_error "Make sure 'podman machine list' shows a running VM."
    exit 1
}

# ---------------------------------------------------------------------------
# Run a command inside the Podman Machine (or locally on native Linux)
# Usage: run_in_machine 'command args'
# ---------------------------------------------------------------------------
run_in_machine() {
    local cmd="$1"
    log_debug "Running command: $cmd"

    if $IS_NATIVE_LINUX; then
        log_debug "Running locally (native Linux)"
        bash -c "$cmd" 2>&1
    elif [[ "$SSH_METHOD" == "ssh" ]]; then
        podman machine ssh -- $cmd
    else
        # Prepend cd / to prevent WSL path translation issues when cwd is on a Windows drive
        wsl -d "$MACHINE_NAME" sh -c "cd / && $cmd"
    fi
}

# ---------------------------------------------------------------------------
# Run a command inside the Podman Machine and capture output
# (or locally on native Linux)
# Usage: result=$(run_in_machine_capture 'command args')
# ---------------------------------------------------------------------------
run_in_machine_capture() {
    local cmd="$1"
    local output=""

    if $IS_NATIVE_LINUX; then
        log_debug "Running locally (native Linux): $cmd"
        output=$(bash -c "$cmd" 2>&1)
    elif [[ "$SSH_METHOD" == "ssh" ]]; then
        output=$(podman machine ssh -- $cmd 2>&1)
    else
        # Prepend cd / to prevent WSL path translation issues when cwd is on a Windows drive
        output=$(wsl -d "$MACHINE_NAME" sh -c "cd / && $cmd" 2>&1)
    fi

    echo "$output"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight() {
    # Check if podman is available
    if ! command -v podman &>/dev/null; then
        log_error "podman is not installed or not in PATH."
        exit 1
    fi

    # Auto-init if no machine exists (Windows/WSL2 only)
    if ! $IS_NATIVE_LINUX; then
        if ! machine_exists; then
            init_machine || {
                log_error "Podman Machine initialization failed."
                log_info "You can init it manually later with: podman machine init && podman machine start"
                exit 1
            }
        elif ! machine_running; then
            log_info "Podman Machine exists but is not running. Starting it..."
            podman machine start 2>&1
            sleep 3
            if ! machine_running; then
                log_error "Failed to start Podman Machine."
                exit 1
            fi
            log_ok "Podman Machine is now running."
        fi

        # Detect the best SSH method
        detect_ssh_method
    else
        log_info "On native Linux, no VM init or SSH method needed."
    fi
}

# ---------------------------------------------------------------------------
# Detect package manager (inside Podman Machine or locally on native Linux)
# ---------------------------------------------------------------------------
detect_pkg_manager() {
    if $IS_NATIVE_LINUX; then
        # Native Linux: check local package manager
        if command -v dnf &>/dev/null; then
            echo "dnf"
        elif command -v yum &>/dev/null; then
            echo "yum"
        elif command -v apt-get &>/dev/null; then
            echo "apt"
        else
            echo "unknown"
        fi
    else
        local pm
        pm=$(run_in_machine_capture '
            if command -v dnf &>/dev/null; then echo "dnf"
            elif command -v yum &>/dev/null; then echo "yum"
            elif command -v apt-get &>/dev/null; then echo "apt"
            else echo "unknown"
            fi
        ')
        echo "$pm"
    fi
}

# ---------------------------------------------------------------------------
# Check if toolkit is already installed
# ---------------------------------------------------------------------------
check_installed() {
    local result
    result=$(run_in_machine_capture '
        if command -v nvidia-ctk &>/dev/null && [ -f /etc/cdi/nvidia.yaml ]; then
            echo "installed"
        elif command -v nvidia-container-runtime &>/dev/null && [ -f /etc/nvidia-container-runtime/config.toml ]; then
            echo "installed"
        else
            echo "not-installed"
        fi
    ')
    echo "$result"
}

# ---------------------------------------------------------------------------
# Verify toolkit installation
# ---------------------------------------------------------------------------
verify_install() {
    log_info "Verifying NVIDIA Container Toolkit installation..."
    echo ""

    local checks_passed=0
    local checks_total=5

    # Check 1: nvidia-ctk binary (or nvidia-container-runtime)
    if run_in_machine_capture 'which nvidia-ctk &>/dev/null || which nvidia-container-runtime &>/dev/null' &>/dev/null; then
        log_ok "NVIDIA toolkit binary found"
        checks_passed=$((checks_passed + 1))
    else
        log_error "NVIDIA toolkit binary NOT found"
    fi

    # Check 2: CDI spec exists
    if run_in_machine_capture 'test -f /etc/cdi/nvidia.yaml' &>/dev/null; then
        log_ok "CDI spec exists at /etc/cdi/nvidia.yaml"
        checks_passed=$((checks_passed + 1))
    else
        log_error "CDI spec NOT found at /etc/cdi/nvidia.yaml"
    fi

    # Check 3: CDI devices visible
    local cdi_devices
    cdi_devices=$(run_in_machine_capture 'nvidia-ctk cdi list 2>/dev/null' || echo "")
    if echo "$cdi_devices" | grep -q "nvidia.com/gpu"; then
        log_ok "CDI devices detected: $cdi_devices"
        checks_passed=$((checks_passed + 1))
    else
        log_error "No CDI devices detected (run 'sudo nvidia-ctk cdi generate')"
    fi

    # Check 4: GPU visible (platform-specific)
    if $IS_NATIVE_LINUX; then
        if run_in_machine_capture 'nvidia-smi &>/dev/null' &>/dev/null; then
            log_ok "GPU visible via nvidia-smi (native Linux)"
        else
            log_error "GPU NOT visible via nvidia-smi — check host NVIDIA driver"
        fi
    else
        if run_in_machine_capture '/usr/lib/wsl/lib/nvidia-smi &>/dev/null' &>/dev/null; then
            log_ok "GPU visible via WSL2 (/usr/lib/wsl/lib/nvidia-smi)"
        else
            log_warn "GPU NOT visible via WSL2 — check NVIDIA Windows driver"
        fi
    fi

    # Check 5: CUDA libraries (platform-specific)
    if $IS_NATIVE_LINUX; then
        if run_in_machine_capture 'ls /usr/lib/*/libcuda.so* &>/dev/null || ls /usr/lib/wsl/lib/libcuda* &>/dev/null' &>/dev/null; then
            log_ok "CUDA libraries found"
        else
            log_error "CUDA libraries NOT found"
        fi
    else
        if run_in_machine_capture 'ls /usr/lib/wsl/lib/libcuda*' &>/dev/null; then
            log_ok "CUDA libraries found in /usr/lib/wsl/lib/"
        else
            log_error "CUDA libraries NOT found in /usr/lib/wsl/lib/"
        fi
    fi

    echo ""
    if [[ $checks_passed -eq $checks_total ]]; then
        log_ok "All $checks_total checks passed. Toolkit is ready."
        return 0
    else
        log_error "$checks_passed/$checks_total checks passed. Something needs attention."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Clean up toolkit
# ---------------------------------------------------------------------------
do_clean() {
    log_warn "Removing NVIDIA Container Toolkit and CDI spec..."
    if $IS_NATIVE_LINUX; then
        local pm
        pm=$(detect_pkg_manager)
        case "$pm" in
            dnf|yum)
                run_in_machine_capture "sudo $pm remove -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1 2>/dev/null || true"
                ;;
            apt)
                run_in_machine_capture "sudo apt-get purge -y nvidia-container-toolkit nvidia-container-runtime libnvidia-container-tools libnvidia-container1 2>/dev/null || true"
                ;;
        esac
        run_in_machine_capture 'sudo rm -f /etc/cdi/nvidia.yaml /etc/nvidia-container-runtime/config.toml'
    else
        run_in_machine_capture '
            rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo
            dnf remove -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1 2>/dev/null || \
            yum remove -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1 2>/dev/null || true
            rm -f /etc/cdi/nvidia.yaml /etc/nvidia-container-runtime/config.toml
            echo "Cleaned."
        '
    fi
    log_ok "Toolkit removed. Run the install command again to reinstall."
}

# ---------------------------------------------------------------------------
# Copy helper scripts to the Podman Machine (or locally on native Linux)
# ---------------------------------------------------------------------------
copy_helper_scripts() {
    local machine_dir="/tmp/agentx-scripts"
    
    # Create directory on the machine
    run_in_machine_capture "mkdir -p $machine_dir"
    
    if $IS_NATIVE_LINUX; then
        # Native Linux: copy from script directory directly
        local script_dir
        script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
        
        if [[ -f "$script_dir/fix-podman-cdi.py" ]]; then
            run_in_machine_capture "cp '$script_dir/fix-podman-cdi.py' $machine_dir/fix-podman-cdi.py"
        fi
        if [[ -f "$script_dir/add-nvidia-runtime.py" ]]; then
            run_in_machine_capture "cp '$script_dir/add-nvidia-runtime.py' $machine_dir/add-nvidia-runtime.py"
        fi
    elif [[ "$SSH_METHOD" == "wsl" ]]; then
        # WSL2: use wslpath to get the Windows path
        local script_dir
        script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
        local win_script_dir
        win_script_dir=$(wslpath -w "$script_dir")
        
        # Copy fix-podman-cdi.py
        if [[ -f "$script_dir/fix-podman-cdi.py" ]]; then
            run_in_machine_capture "cp \"$(wslpath -w "$script_dir/fix-podman-cdi.py")\" $machine_dir/fix-podman-cdi.py 2>/dev/null || true"
        fi
        
        # Copy add-nvidia-runtime.py
        if [[ -f "$script_dir/add-nvidia-runtime.py" ]]; then
            run_in_machine_capture "cp \"$(wslpath -w "$script_dir/add-nvidia-runtime.py")\" $machine_dir/add-nvidia-runtime.py 2>/dev/null || true"
        fi
    fi
    
    # Verify scripts exist
    if ! run_in_machine_capture "test -f $machine_dir/fix-podman-cdi.py" &>/dev/null; then
        log_warn "Could not copy helper scripts. CDI fix may need manual intervention."
        return 1
    fi
    
    return 0
}

# ---------------------------------------------------------------------------
# Install toolkit
# ---------------------------------------------------------------------------
do_install() {
    local pm
    pm=$(detect_pkg_manager)

    if [[ "$pm" == "unknown" ]]; then
        log_error "Could not detect package manager."
        exit 1
    fi

    log_info "Detected platform: $([ $IS_NATIVE_LINUX ] && echo 'native Linux' || echo 'Podman Machine')"
    log_info "Detected package manager: $pm"
    log_info "Installing NVIDIA Container Toolkit..."
    echo ""

    if $IS_NATIVE_LINUX; then
        # ---- Native Linux install ----
        log_info "Adding NVIDIA Container Toolkit repository..."
        case "$pm" in
            dnf|yum)
                # RHEL/Fedora: use RPM repo
                run_in_machine_capture 'curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null'
                ;;
            apt)
                # Debian/Ubuntu: use apt repo
                run_in_machine_capture 'curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && \
                    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                    sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" | \
                    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list'
                ;;
        esac

        log_info "Installing packages (this may take a minute)..."
        case "$pm" in
            dnf|yum)
                run_in_machine_capture 'sudo dnf install -y nvidia-container-toolkit'
                ;;
            apt)
                run_in_machine_capture 'sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit'
                ;;
        esac

        # Generate CDI spec
        log_info "Generating CDI specification..."
        run_in_machine_capture 'sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml'

        # Copy helper scripts for Podman config fixes
        log_info "Preparing Podman configuration fixes..."
        copy_helper_scripts || true

        # Fix CDI spec dirs in containers.conf
        log_info "Enabling CDI spec directories in containers.conf..."
        run_in_machine 'sudo python3 /tmp/agentx-scripts/fix-podman-cdi.py && sudo cp /tmp/containers.conf /usr/share/containers/containers.conf'

        # Configure NVIDIA runtime
        log_info "Configuring NVIDIA runtime in containers.conf..."
        run_in_machine 'sudo python3 /tmp/agentx-scripts/add-nvidia-runtime.py'

        # Reload systemd if needed (native Linux)
        log_info "Reloading systemd configuration..."
        run_in_machine 'sudo systemctl restart podman 2>/dev/null || true'

    else
        # ---- Podman Machine (WSL2) install ----
        log_info "Adding NVIDIA Container Toolkit repository..."
        run_in_machine_capture 'curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null'

        log_info "Installing packages (this may take a minute)..."
        run_in_machine_capture 'sudo dnf install -y nvidia-container-toolkit'

        log_info "Generating CDI specification..."
        run_in_machine_capture 'sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml'

        log_info "Preparing Podman configuration fixes..."
        copy_helper_scripts || true

        log_info "Enabling CDI spec directories in containers.conf..."
        run_in_machine 'sudo python3 /tmp/agentx-scripts/fix-podman-cdi.py && sudo cp /tmp/containers.conf /usr/share/containers/containers.conf'

        log_info "Configuring NVIDIA runtime in containers.conf..."
        run_in_machine 'sudo python3 /tmp/agentx-scripts/add-nvidia-runtime.py'
    fi

    echo ""
    log_ok "Installation complete."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Handle init-only mode (no-op on native Linux)
    if $INIT_ONLY; then
        preflight
        if $IS_NATIVE_LINUX; then
            log_info "On native Linux, no Podman Machine init is needed."
        fi
        exit 0
    fi

    # Handle clean mode
    if $CLEAN; then
        preflight
        do_clean
        exit 0
    fi

    # Handle verify-only mode
    if $VERIFY_ONLY; then
        preflight
        local status
        status=$(check_installed)
        if [[ "$status" == "installed" ]]; then
            log_ok "NVIDIA Container Toolkit is already installed."
            verify_install
        else
            log_warn "Toolkit is NOT installed."
            log_info "Run without --verify to install it."
        fi
        exit 0
    fi

    # Normal install flow
    preflight

    local status
    status=$(check_installed)

    if [[ "$status" == "installed" && "$FORCE" == "false" ]]; then
        log_ok "NVIDIA Container Toolkit is already installed."
        log_info "Run with --force to reinstall."
        echo ""
        verify_install
        exit 0
    fi

    if [[ "$status" == "installed" && "$FORCE" == "true" ]]; then
        log_warn "Force reinstalling (existing installation will be replaced)..."
        # Remove old CDI spec
        run_in_machine_capture 'sudo rm -f /etc/cdi/nvidia.yaml /etc/nvidia-container-runtime/config.toml 2>/dev/null || true'
    fi

    do_install
    echo ""
    verify_install
}

main "$@"
