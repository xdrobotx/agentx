# NVIDIA GPU Setup for AgentX

This guide covers GPU setup for running AgentX containers with NVIDIA GPU
acceleration. It supports three environments:

| Environment | GPU Passthrough Method | Notes |
|-------------|----------------------|-------|
| **Windows + WSL2** | WSL2 manual device passthrough | Default setup |
| **Native Linux (RHEL/Fedora)** | CDI or NVIDIA runtime | Native Podman |
| **Native Linux (Debian/Ubuntu)** | CDI or NVIDIA runtime | Native Podman |

---

## Quick Setup by Platform

### Windows (WSL2) — One-Command Setup

```bash
just nvidia-init        # Initialize Podman Machine (one-time)
just nvidia-toolkit     # Install NVIDIA Container Toolkit
just nvidia-test        # Verify GPU passthrough works
```

### Native Linux — One-Command Setup

```bash
# On RHEL/Fedora/CentOS:
just nvidia-toolkit --platform rhel

# On Debian/Ubuntu:
just nvidia-toolkit --platform debian
```

The script auto-detects your platform. If you're on native Linux, it installs
the toolkit directly on the host (no Podman Machine needed).

---

## Architecture Overview

### Windows + WSL2

```
┌─────────────────────────────────────────────────────────┐
│  Windows 11 (NVIDIA Driver 581.57)                      │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  WSL2 (Kernel 6.18.33)                            │  │
│  │                                                   │  │
│  │  /dev/dxg          ← NVIDIA WSL2 device node      │  │
│  │  /usr/lib/wsl/lib/ ← CUDA libraries               │  │
│  │  /usr/lib/wsl/drivers/ ← WSL2 driver binaries     │  │
│  │                                                   │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │  Podman Machine (Fedora 44, crun 1.28)      │  │  │
│  │  │                                             │  │  │
│  │  │  /etc/cdi/nvidia.yaml  ← CDI spec           │  │  │
│  │  │  /usr/bin/nvidia-container-runtime          │  │  │
│  │  │                                             │  │  │
│  │  │  ┌───────────────────────────────────────┐  │  │  │
│  │  │  │  Container                            │  │  │  │
│  │  │  │  /dev/dxg      ← mounted via --device  │  │  │  │
│  │  │  │  /usr/lib/wsl/lib/ ← mounted via -v    │  │  │  │
│  │  │  └───────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Native Linux

```
┌─────────────────────────────────────────────────────────┐
│  Native Linux (RHEL/Fedora/Debian/Ubuntu)               │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Podman (direct, no VM)                            │  │
│  │                                                   │  │
│  │  /dev/nvidia0      ← NVIDIA device nodes          │  │
│  │  /dev/nvidia-uvm   ← Unified Memory               │  │
│  │  /usr/lib/x86_64-linux-gnu/libcuda*              │  │  │
│  │                                                   │  │
│  │  ┌───────────────────────────────────────────┐    │  │
│  │  │  Container (via CDI or nvidia runtime)    │    │  │
│  │  │  GPU devices + CUDA libs auto-injected    │    │  │
│  │  └───────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Detailed Setup

### Environment 1: Windows + WSL2

#### Prerequisites

1. **Windows 11 22H2+** — Required for WSL2 NVIDIA driver support
2. **NVIDIA Windows Driver** — Version 581.57 or newer
   - Download from [NVIDIA Driver Downloads](https://www.nvidia.com/drivers)
   - The Windows driver auto-exposes GPU devices to WSL2
   - No separate WSL2 driver installation needed
3. **WSL2** — Built into Windows 11
4. **Podman CLI** — Installed in Windows

#### Setup Steps

```bash
# 1. Initialize Podman Machine (creates a Fedora 44 VM)
just nvidia-init

# 2. Install NVIDIA Container Toolkit inside the Podman Machine
just nvidia-toolkit

# 3. Verify the installation
just nvidia-verify

# 4. Test GPU passthrough
just nvidia-test
```

#### What the Script Does

1. Detects the host OS (Windows vs WSL2 vs native Linux)
2. Creates and starts the Podman Machine if needed
3. Installs `nvidia-container-toolkit` inside the VM
4. Generates the CDI spec at `/etc/cdi/nvidia.yaml`
5. Fixes Podman config (enables CDI spec dirs — Fedora ships them commented out)
6. Configures the NVIDIA runtime as an alternative
7. Runs 5 verification checks

#### Remote Execution

The script auto-detects the best way to execute commands inside the Podman Machine:

| Host Environment | Method | Command |
|-----------------|--------|---------|
| Windows PowerShell/CMD | `podman machine ssh` | `podman machine ssh -- <cmd>` |
| WSL2 terminal | `wsl -d` | `wsl -d <machine_name> sh -c '<cmd>'` |

The `wsl -d` method is preferred from WSL2 because `podman machine ssh` fails
when run from within WSL2 targeting another WSL2 distro.

### Environment 2: Native Linux (RHEL/Fedora/CentOS)

#### Prerequisites

1. **Podman** — `sudo dnf install podman`
2. **NVIDIA Linux Driver** — Installed on the host
   - Verify with: `nvidia-smi`
3. **NVIDIA Container Toolkit** — Installed via the script

#### Setup Steps

```bash
# The script auto-detects RHEL/Fedora and installs accordingly
just nvidia-toolkit

# Or explicitly specify the platform:
just nvidia-toolkit --platform rhel

# Verify:
just nvidia-verify

# Test:
just nvidia-test
```

#### What the Script Does

On native Linux, the script:

1. Detects the package manager (`dnf` or `yum` for RHEL, `apt` for Debian)
2. Adds the NVIDIA Container Toolkit repository
3. Installs the toolkit directly on the host (no VM needed)
4. Configures Podman to use the NVIDIA runtime:
   ```toml
   [[engine.runtimes]]
   name = "nvidia"
   path = "/usr/bin/nvidia-container-runtime"
   ```
5. Generates the CDI spec at `/etc/cdi/nvidia.yaml`
6. Enables CDI spec directories in `/etc/containers/containers.conf`
7. Runs verification checks

### Environment 3: Native Linux (Debian/Ubuntu)

#### Prerequisites

1. **Podman** — `sudo apt install podman`
2. **NVIDIA Linux Driver** — Installed on the host
   - Verify with: `nvidia-smi`
3. **NVIDIA Container Toolkit** — Installed via the script

#### Setup Steps

```bash
# The script auto-detects Debian/Ubuntu and installs accordingly
just nvidia-toolkit

# Or explicitly specify the platform:
just nvidia-toolkit --platform debian

# Verify:
just nvidia-verify

# Test:
just nvidia-test
```

---

## GPU Passthrough Modes

### How `run-llama.sh` Chooses a Mode

The container runner auto-detects the GPU passthrough method:

```bash
detect_gpu_passthrough() {
    # 1. Check for CDI support
    if podman info 2>/dev/null | grep -qi cdi; then
        GPU_PASSTHROUGH_METHOD="cdi"
    # 2. Check for WSL2 NVIDIA device
    elif [[ -e /dev/dxg ]]; then
        GPU_PASSTHROUGH_METHOD="wsl2"
    else
        GPU_PASSTHROUGH_METHOD="none"
    fi
}
```

### CDI Mode (Native Linux, or future crun >= 1.29)

When CDI is supported, the container runner uses:

```bash
podman run --rm --device nvidia.com/gpu=all \
    --security-opt=label=disable \
    <image> <args>
```

This is the cleanest approach — Podman reads the CDI spec and automatically
injects GPU devices and libraries.

### WSL2 Manual Mode (Windows + WSL2)

When CDI is not available, the runner uses manual device passthrough:

```bash
podman run --rm \
    --device=/dev/dxg \
    -v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro \
    -v /usr/lib/wsl/drivers/nv_dispsi.inf_amd64_671c0a23616db704:/usr/lib/wsl/drivers/nv_dispsi.inf_amd64_671c0a23616db704:ro \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e LD_LIBRARY_PATH=/usr/lib/wsl/lib:/usr/lib/wsl/drivers/nv_dispsi.inf_amd64_671c0a23616db704 \
    <image> <args>
```

| Flag | Purpose |
|------|---------|
| `--device=/dev/dxg` | Exposes the WSL2 NVIDIA device node |
| `-v /usr/lib/wsl/lib:ro` | Mounts CUDA libraries (libcuda, libnvidia-ml, etc.) |
| `-v /usr/lib/wsl/drivers/...:ro` | Mounts WSL2 driver binaries (DLLs, firmware) |
| `NVIDIA_DRIVER_CAPABILITIES=all` | Tells the container which driver features to enable |
| `NVIDIA_VISIBLE_DEVICES=all` | Makes all GPUs visible inside the container |
| `LD_LIBRARY_PATH=...` | Ensures the container finds CUDA libraries |

### NVIDIA Runtime Mode (Native Linux)

On native Linux with the NVIDIA runtime configured, the runner uses:

```bash
podman run --rm --runtime nvidia --gpus=all \
    <image> <args>
```

### Native Linux CDI Mode

On native Linux with CDI support:

```bash
podman run --rm --device nvidia.com/gpu=all \
    <image> <args>
```

---

## GPU Routing by Compute Capability

| GPU | Compute Capability | Recommended CUDA Version | Container Image |
|-----|-------------------|-------------------------|-----------------|
| GTX 1060 (Pascal) | 6.1 | CUDA 12.9 | `llama-server:cuda12.9` |
| RTX 3050 (Ampere) | 8.6 | CUDA 12.9 or 13.2 | `llama-server:cuda13.2` |

**Important:** CUDA 13.x drops offline compilation support for compute
capabilities below 7.5 (Maxwell, Pascal, Volta). The GTX 1060 (CC 6.1) **will
not work** with CUDA 13.2 builds. Only the RTX 3050 (CC 8.6) can use CUDA 13.2.

---

## Commands Reference

### NVIDIA Toolkit Commands

```bash
just nvidia-init          # Initialize Podman Machine (Windows/WSL2 only)
just nvidia-toolkit       # Install NVIDIA Container Toolkit (auto-detects platform)
just nvidia-toolkit --force   # Force reinstall
just nvidia-toolkit --verify  # Check installation status
just nvidia-verify        # Quick status check (same as --verify)
just nvidia-clean         # Remove toolkit and CDI spec
just nvidia-test          # Test GPU passthrough in a container
```

### Container Run Commands

```bash
just run --gpu 12.9 --model /path/to/model.gguf
just run --gpu 13.2 --model /path/to/model.gguf --port 9698
just run_config --config containers/configs/model.json
just run_router --model-a /path/a.gguf --model-b /path/b.gguf
```

### Status and Management

```bash
just status               # Show running containers
just stop                 # Stop all containers
just stop_12.9            # Stop CUDA 12.9 container
just stop_13.2            # Stop CUDA 13.2 container
just clean_containers     # Remove stopped containers
```

---

## Troubleshooting

### GPU Not Visible in Container

1. **Check NVIDIA device:**
   ```bash
   # WSL2
   ls -la /dev/dxg
   /usr/lib/wsl/lib/nvidia-smi

   # Native Linux
   ls -la /dev/nvidia*
   nvidia-smi
   ```

2. **Check CDI spec:**
   ```bash
   cat /etc/cdi/nvidia.yaml
   nvidia-ctk cdi list
   ```

3. **Run the test:**
   ```bash
   just nvidia-test
   ```

### Container Fails with GPU Flags

If you see errors like `stat E: no such file or directory`, the Windows
terminal is translating `/dev/dxg` to a Windows path. Run the command
inside the WSL2 machine or use the `just` commands which handle this
automatically.

### Podman Machine Connection Errors

```
Cannot connect to Podman. Please verify your connection...
```

Restart the machine:

```bash
podman machine stop
podman machine start
```

### NVIDIA Runtime Not Found

```
Error: default OCI runtime "nvidia" not found
```

Ensure the NVIDIA runtime is configured:

```bash
cat /etc/containers/containers.conf | grep -A2 nvidia
```

If missing, run `just nvidia-toolkit` to reconfigure.

### CDI Spec Dirs Commented Out

If `podman info` doesn't show CDI-related output, the CDI spec directories
may be commented out. The setup script fixes this automatically.

---

## File Reference

| File | Purpose |
|------|---------|
| `containers/scripts/setup-nvidia-toolkit.sh` | Main setup script (all platforms) |
| `containers/scripts/fix-podman-cdi.py` | CDI config fixer |
| `containers/scripts/add-nvidia-runtime.py` | NVIDIA runtime config |
| `containers/scripts/test-gpu.sh` | GPU passthrough test |
| `containers/run-llama.sh` | Container runner with auto-detection |
| `justfile` | `just` command definitions |

---

## Version Information

| Component | Version |
|-----------|---------|
| Windows NVIDIA Driver | 581.57 |
| WSL2 Kernel | 6.18.33.2-microsoft-standard |
| Podman | 5.8.6 |
| crun | 1.28 |
| Fedora (Podman Machine) | 44 |
| NVIDIA Container Toolkit | 1.20.0 |
| nvidia-ctk | 1.20.0 |

---

## Upgrade Path

To upgrade to full CDI mode when crun 1.29+ becomes available:

1. Upgrade crun in the Podman Machine:
   ```bash
   wsl -d podman-machine-default sudo dnf upgrade -y crun
   ```

2. Restart Podman:
   ```bash
   podman machine stop
   podman machine start
   ```

3. Verify CDI support:
   ```bash
   podman info | grep -i cdi
   ```

4. The `run-llama.sh` script will automatically switch to CDI mode if
   detected.
