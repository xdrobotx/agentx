# Usage Guide

Complete reference for running and managing llama.cpp containers with agentx.

---

## Quick Reference

| Category | Command | Description |
|----------|---------|-------------|
| **Run** | `just run --gpu 12.9 --model <path>` | Run a single server |
| **Run** | `just run_config --config <file>` | Run from JSON config |
| **Run** | `just run_router --model-a <path> --model-b <path>` | Router mode |
| **Status** | `just status` | Show container status |
| **Stop** | `just stop` | Stop all containers |
| **Config** | `just config_list` | List available configs |
| **Config** | `just config_validate <file>` | Validate a config |
| **Build** | `just container_build_all` | Build all images |
| **Clean** | `just clean_all` | Clean all artifacts |
| **Info** | `just info` | Show system info |

---

## Running a Single Server

### Basic usage

```bash
just run --gpu 12.9 --model /mnt/f/models/model.gguf
```

### With custom port

```bash
just run --gpu 13.3 --model /mnt/f/models/model.gguf --port 9696
```

### With GPU layer control

```bash
just run --gpu 12.9 --model /mnt/f/models/model.gguf --n-gpu-layers 33
```

### GPU versions

| `--gpu` value | CUDA Version | Image | Target GPU |
|---------------|-------------|-------|------------|
| `12.9` | CUDA 12.9 | `llama-server:cuda12.9` | GTX 1060 (compute 6.1) |
| `13.3` | CUDA 13.3 | `llama-server:cuda13.3` | RTX 3050 (compute 8.6) |

---

## Running from a JSON Config

### List available configs

```bash
just config_list
```

### Validate a config

```bash
just config_validate containers/configs/qwen-3.6-35B-A3B-coding.json
```

### Preview generated CLI args (dry run)

```bash
just config_show containers/configs/qwen-3.6-35B-A3B-coding.json
```

### Run with a config

```bash
just run_config containers/configs/qwen-3.6-35B-A3B-coding.json
```

---

## Router Mode

Run multiple backends with a central router for load balancing and model switching.

```bash
just run_router \
  --model-a /mnt/f/models/model-a.gguf \
  --model-b /mnt/f/models/model-b.gguf
```

### Router ports

| Service | Port | Description |
|---------|------|-------------|
| Router | 9696 | Entry point — routes to backends |
| Backend 1 | 9697 (default) | First model backend |
| Backend 2 | 9698 (default) | Second model backend |

### With custom tags

```bash
just run_router \
  --model-a /mnt/f/models/coding.gguf \
  --model-b /mnt/f/models/creative.gguf \
  --model-a-tag coding \
  --model-b-tag creative
```

---

## Managing Containers

### Check status

```bash
just status
```

### Stop containers

```bash
just stop                    # Stop all
just stop_12_9               # Stop CUDA 12.9 only
just stop_13_3               # Stop CUDA 13.3 only
```

### Clean up

```bash
just clean_containers        # Remove stopped containers
just clean_all               # Clean all build artifacts
```

---

## Network Management

```bash
just network_create          # Create agentx-network (one-time)
just network_status          # List Podman networks
```

---

## API Endpoints

Once a container is running, the llama-server exposes these endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/chat/completions` | POST | Chat completions (OpenAI-compatible) |
| `/v1/completions` | POST | Text completions |
| `/v1/models` | GET | List available models |
| `/health` | GET | Server health check |
| `/metrics` | GET | Prometheus metrics |

### Example: Chat

```bash
curl http://localhost:9696/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-3.6-35B-A3B-coding",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain quantum computing."}
    ],
    "temperature": 0.7,
    "max_tokens": 512
  }'
```

---

## Build Commands

| Command | Description |
|---------|-------------|
| `just update` | Pull latest llama.cpp source |
| `just update_branch <tag>` | Pull a specific branch/tag |
| `just build-all` | Build both CUDA versions (native) |
| `just container_build_all` | Build all container images |

---

## Useful Aliases

Add to your `~/.bashrc`:

```bash
# Quick status
alias ax-status='just status'

# Quick stop
alias ax-stop='just stop'

# Run default model
alias ax-run='just run_config --config containers/configs/qwen-3.6-35B-A3B-coding.json'

# List configs
alias ax-configs='just config_list'
```
