# Router Mode

Run multiple llama-server backends behind a central router for load balancing and model switching.

---

## What is Router Mode?

Router mode starts multiple llama-server containers (one per GPU/CUDA version) behind a central router container. The router:

- Receives all incoming requests on a single port
- Routes requests to backends based on tags
- Allows switching between models without restarting

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│  Client  │────▶│  Router      │────▶│ Backend 1    │
│          │     │  (port 9696) │     │ (GTX 1060)   │
└──────────┘     └──────────────┘     └──────────────┘
                         │
                         ▼
                   ┌──────────────┐
                   │ Backend 2    │
                   │ (RTX 3050)   │
                   └──────────────┘
```

---

## Quick Start

```bash
just run_router \
  --model-a /mnt/f/models/coding-model.gguf \
  --model-b /mnt/f/models/creative-model.gguf
```

This starts:
- **Router** on port 9696
- **Backend 1** (CUDA 12.9, GTX 1060) on port 9697
- **Backend 2** (CUDA 13.2, RTX 3050) on port 9698

---

## With Custom Tags

Assign human-readable tags to each backend:

```bash
just run_router \
  --model-a /mnt/f/models/coding.gguf \
  --model-b /mnt/f/models/creative.gguf \
  --model-a-tag coding \
  --model-b-tag creative
```

---

## Routing to a Specific Backend

Send requests to the router with a tag:

```bash
curl http://localhost:9696/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "coding",
    "messages": [{"role": "user", "content": "Write some code."}],
    "temperature": 0.3
  }'
```

The router routes based on the `model` field matching the assigned tag.

---

## Ports

| Service | Default Port | Purpose |
|---------|-------------|---------|
| Router | 9696 | Entry point for all requests |
| Backend 1 | 9697 | First backend (CUDA 12.9) |
| Backend 2 | 9698 | Second backend (CUDA 13.2) |

---

## Managing Router Mode

### Stop all backends and router

```bash
just stop
```

### Check status

```bash
just status
```

### Restart

```bash
just run_router \
  --model-a /path/to/model-a.gguf \
  --model-b /path/to/model-b.gguf
```

---

## Use Cases

### A/B Testing

Run two versions of the same model and route traffic between them:

```bash
just run_router \
  --model-a /mnt/f/models/model-v1.gguf \
  --model-b /mnt/f/models/model-v2.gguf \
  --model-a-tag v1 \
  --model-b-tag v2
```

### Skill-based routing

Use different models for different tasks:

```bash
just run_router \
  --model-a /mnt/f/models/coding.gguf \
  --model-b /mnt/f/models/creative.gguf \
  --model-a-tag coding \
  --model-b-tag creative
```

### Hardware-aware routing

Route to the best GPU for the workload:

```bash
just run_router \
  --model-a /mnt/f/models/large-model.gguf \
  --model-b /mnt/f/models/small-model.gguf \
  --model-a-tag large \
  --model-b-tag small
```

---

## Advanced: Custom Ports

```bash
just run_router \
  --model-a /mnt/f/models/model-a.gguf \
  --model-b /mnt/f/models/model-b.gguf \
  --port-a 8001 \
  --port-b 8002
```

---

## Troubleshooting

### Router not connecting to backends

1. Ensure the Podman network exists:
   ```bash
   just network_create
   ```

2. Check that backends are running:
   ```bash
   just status
   ```

3. Verify network connectivity:
   ```bash
   podman exec llama-cpp-12.9 ping llama-cpp-13.2
   ```

### Backend not responding

Check the container logs:

```bash
podman logs llama-cpp-12.9
podman logs llama-cpp-13.2
podman logs llama-router
```

### Port conflicts

If a port is already in use, specify custom ports:

```bash
just run_router \
  --model-a /path/a.gguf \
  --model-b /path/b.gguf \
  --port-a 9700 \
  --port-b 9701
```
