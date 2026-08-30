# Build Guide

Build llama.cpp from source (native) or build Podman container images.

---

## Prerequisites

### WSL2 Environment

- Ubuntu on WSL2
- NVIDIA drivers (Windows 11 22H2+)
- CUDA toolkit (for native builds)
- Build essentials: `sudo apt install build-essential git cmake`

### Windows Environment

- Windows 11 22H2+
- NVIDIA drivers
- PowerShell 7+
- CMake and a C++ compiler (MSVC)

---

## Container Builds (Recommended)

### Build all images

```bash
just container_build_all
```

### Build individual images

```bash
just container_build_12_9   # CUDA 12.9 — for GTX 1060 (compute 6.1)
just container_build_13_2   # CUDA 13.2 — for RTX 3050 (compute 8.6)
```

### List built images

```bash
just container_list
```

---

## Native Builds (WSL2)

### Build for a specific CUDA version

```bash
just build_12_9   # CUDA 12.9
just build_13_2   # CUDA 13.2
```

### Build both versions

```bash
just build-all
```

---

## Native Builds (Windows/PowerShell)

> Run from PowerShell, not WSL2.

```powershell
just build_windows_12_9   # CUDA 12.9
just build_windows_13_2   # CUDA 13.2
```

---

## Update llama.cpp Submodule

### Pull latest main branch

```bash
just update
```

### Pull a specific branch or tag

```bash
just update_branch v1.7.3
```

---

## Cleanup

### Clean native build artifacts

```bash
just clean_native          # WSL2
just clean_native_windows  # PowerShell
```

### Clean WSL2 build artifacts

```bash
just clean_wsl2
```

### Clean all artifacts

```bash
just clean_all
```

### Remove stopped containers

```bash
just clean_containers
```

---

## Build Scripts

| Script | Location | Platform | Purpose |
|--------|----------|----------|---------|
| `build.sh` | `source-build/scripts/` | WSL2/Linux | Native build (bash) |
| `build.ps1` | `source-build/scripts/` | Windows | Native build (PowerShell) |
| `clean.sh` | `source-build/scripts/` | WSL2/Linux | Clean build artifacts |
| `clean.ps1` | `source-build/scripts/` | Windows | Clean build artifacts |

---

## CUDA Architecture Reference

| CUDA Version | Supported Architectures | Target GPUs |
|--------------|------------------------|-------------|
| 12.9 | `sm_61` | GTX 1060, GTX 1080, RTX 20xx |
| 13.2 | `sm_61`, `sm_86` | GTX 10xx, RTX 30xx, RTX 40xx |

---

## Troubleshooting

### Build fails with CUDA errors

Ensure your NVIDIA drivers support the target CUDA version. Check with:

```bash
nvidia-smi
```

### Container build fails

Make sure Podman is running and you have NVIDIA container runtime:

```bash
podman info | grep -i nvidia
```

### Path resolution issues

Ensure `$LLAMA_MODELS_PATH` is set in your environment:

```bash
echo $LLAMA_MODELS_PATH
```
