# Quick Start Guide

Get up and running with agentx in under 5 minutes.

---

## 1. Setup

### Install prerequisites

Ensure you have the following installed:

- **Podman** — Container runtime
- **just** — Build automation tool (`cargo install just` or `sudo apt install just`)
- **Python 3** — For config parsing
- **NVIDIA drivers** — Windows 11 22H2+ with WSL2 GPU passthrough

### Set up your environment

Add to your `~/.bashrc` (WSL2):

```bash
# Point to your GGUF model directory
export LLAMA_MODELS_PATH="/mnt/f/models"
```

Then reload:

```bash
source ~/.bashrc
```

### Create the Podman network

```bash
just network_create
```

This creates the `agentx-network` that containers use to communicate (required for router mode).

---

## 2. Build Container Images

Build both CUDA versions:

```bash
just container_build_all
```

Or build individually:

```bash
just container_build_12_9   # For GTX 1060 (CUDA 12.9)
just container_build_13_2   # For RTX 3050 (CUDA 13.2)
```

Verify images:

```bash
just container_list
```

---

## 3. Run a Model

### Option A: Using a pre-built config (recommended)

```bash
just run_config --config containers/configs/qwen-3.6-35B-A3B-coding.json
```

### Option B: Direct command

```bash
just run --gpu 12.9 --model /mnt/f/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf
```

Or with a custom port:

```bash
just run --gpu 13.2 --model /mnt/f/models/model.gguf --port 9698
```

### Option C: Specify GPU layers

```bash
just run --gpu 12.9 --model /mnt/f/models/model.gguf --n-gpu-layers 99
```

---

## 4. Interact with the Server

Once a container is running, the llama-server exposes an OpenAI-compatible API:

```bash
# Chat endpoint
curl http://localhost:9696/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-3.6-35B-A3B-coding",
    "messages": [{"role": "user", "content": "Hello, who are you?"}]
  }'

# Completions endpoint
curl http://localhost:9696/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-3.6-35B-A3B-coding",
    "prompt": "The quick brown fox"
  }'
```

---

## 5. Manage Containers

| Action | Command |
|--------|---------|
| Check status | `just status` |
| Stop a specific container | `just stop_12_9` or `just stop_13_2` |
| Stop all containers | `just stop` |
| Remove stopped containers | `just clean_containers` |

---

## GPU Setup (One-Time)

### Prerequisites

- **Windows 11 22H2+** with NVIDIA driver 581.57+ (WSL2 GPU passthrough)
- **Native Linux** with NVIDIA driver and `nvidia-smi` working

### Install the NVIDIA Container Toolkit

**WSL2/Windows:**

```bash
just nvidia-init        # Initialize Podman Machine (one-time)
just nvidia-toolkit     # Install toolkit inside the machine
```

**Native Linux (auto-detects platform):**

```bash
just nvidia-toolkit
```

**Force a specific platform** (if auto-detection fails):

```bash
just nvidia-toolkit --platform rhel     # RHEL/Fedora/CentOS
just nvidia-toolkit --platform debian   # Debian/Ubuntu
```

### Verify

```bash
just nvidia-verify   # Check installation status
just nvidia-test     # Test GPU passthrough in a container
```

> For full GPU setup documentation including architecture diagrams, troubleshooting, and version info, see [NVIDIA GPU Setup](nvidia-gpu-setup.md).

---

## 6. Next Steps

- **[NVIDIA GPU Setup](nvidia-gpu-setup.md)** — Complete GPU passthrough guide
- **[Usage Guide](usage.md)** — Full reference for all commands and options
- **[Configuration](configuration.md)** — How to create custom model configs
- **[Router Mode](router.md)** — Multi-backend load-balanced inference
- **[Build Guide](build.md)** — Native builds from source
