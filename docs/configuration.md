# Configuration Guide

Reference for model configuration files and the parameter mapping system.

---

## Overview

agentx uses a two-layer configuration system:

1. **Model Config** (`containers/configs/*.json`) — Defines which model to run and its parameters.
2. **Parameter Map** (`containers/param-map.json`) — Maps config keys to llama-server CLI flags.

The `parser.py` script reads both files and generates a single-line llama-server command.

---

## Model Config File Format

### Required fields

| Key | Type | Description |
|-----|------|-------------|
| `model` | string | Model identifier (name) |
| `model_path` | string | Full path to the GGUF file (supports `$LLAMA_MODELS_PATH`) |

### Optional fields

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cuda_version` | string | `12.9` | CUDA version for container selection |
| `mmproj` | string | — | Path to multimodal projector file |
| `host` | string | `0.0.0.0` | Bind address |
| `port` | int | `9696` | HTTP port |
| `ctx_size` | int | `4096` | Context size (tokens) |
| `predict` | int | `512` | Max tokens to predict |
| `batch_size` | int | `2048` | Batch size for processing |
| `ubatch_size` | int | `512` | Ubatch size (micro-batch) |
| `parallel` | int | `1` | Number of parallel sequences |
| `threads` | int | `4` | Number of CPU threads |
| `gpu_layers` | string | `all` | GPU offload layers (number or "all") |
| `temperature` | float | `0.8` | Sampling temperature |
| `top_p` | float | `0.95` | Top-p sampling threshold |
| `top_k` | int | `40` | Top-k sampling threshold |
| `min_p` | float | `0.05` | Minimum-p sampling threshold |
| `repeat_penalty` | float | `1.1` | Repeat penalty |
| `presence_penalty` | float | `0.0` | Presence penalty |
| `frequency_penalty` | float | `0.0` | Frequency penalty |
| `flash_attn` | bool | `false` | Enable Flash Attention |
| `cache_type_k` | string | `f16` | KV cache type for K |
| `cache_type_v` | string | `f16` | KV cache type for V |
| `reasoning` | bool | `false` | Enable reasoning mode |
| `reasoning_budget` | int | `0` | Reasoning token budget |
| `reasoning_preserve` | bool | `false` | Preserve reasoning output |
| `jinja` | bool | `false` | Use Jinja chat template |
| `no_mmap` | bool | `false` | Disable memory-mapped file loading |
| `load_mode` | string | `default` | Model loading mode |
| `cpu_moe` | bool | `false` | Offload MoE layers to CPU |
| `cpu_moe_draft` | bool | `false` | Offload MoE draft layers to CPU |
| `fit` | string | `off` | Fit mode |
| `cache_ram` | int | `0` | Cache RAM size in MB |
| `cache_prompt` | bool | `false` | Cache prompt |
| `split_mode` | string | `default` | Split mode for multi-GPU |
| `spec_type` | string | `default` | Speculative decoding type |
| `spec_draft_n_max` | int | `0` | Speculative draft N max |
| `spec_draft_n_min` | int | `0` | Speculative draft N min |
| `spec_draft_type_k` | string | `f16` | Speculative draft KV cache type K |
| `spec_draft_type_v` | string | `f16` | Speculative draft KV cache type V |
| `image_min_tokens` | int | `0` | Minimum image tokens |
| `chat_template_kwargs` | string | `""` | JSON string of chat template kwargs |

### Internal fields (prefixed with `_`)

Fields starting with `_` are ignored by the parser:

```json
{
  "_comment": "This is a comment — ignored by the parser",
  "_comment2": "Another comment"
}
```

---

## Example Config

```json
{
    "_comment": "Qwen 3.6 35B-A3B Coding — MoE with speculative decoding",
    "model": "qwen-3.6-35B-A3B-coding",
    "model_path": "$LLAMA_MODELS_PATH/qwen-3.6-35B-A3B/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf",
    "mmproj": "$LLAMA_MODELS_PATH/qwen-3.6-35B-A3B/mmproj-Qwen3.6-35B-A3B-F16.gguf",
    "cuda_version": "12.9",

    "host": "0.0.0.0",
    "port": 9696,
    "ctx_size": 262144,
    "parallel": 1,
    "threads": 9,
    "gpu_layers": "all",
    "cpu_moe": true,
    "cpu_moe_draft": true,
    "fit": "off",
    "flash_attn": true,
    "cache_type_k": "q4_0",
    "cache_type_v": "q4_0",
    "temperature": 0.96,
    "top_p": 0.95,
    "reasoning": true,
    "reasoning_budget": 2048,
    "jinja": true
}
```

---

## Creating a Custom Config

1. Copy an existing config as a template:
   ```bash
   cp containers/configs/qwen-3.6-35B-A3B-coding.json containers/configs/my-model.json
   ```

2. Edit the values:
   - `model` — Your model name
   - `model_path` — Full path to your GGUF file
   - `cuda_version` — Match your GPU (12.9 or 13.2)
   - Adjust parameters as needed

3. Validate:
   ```bash
   just config_validate containers/configs/my-model.json
   ```

4. Preview the generated CLI:
   ```bash
   just config_show containers/configs/my-model.json
   ```

5. Run:
   ```bash
   just run_config --config containers/configs/my-model.json
   ```

---

## Parameter Map Reference

The `param-map.json` file maps each config key to its corresponding llama-server flag. This allows the config to use short, readable keys while the parser generates correct CLI flags.

Example mapping:

| Config Key | CLI Flag | Type | Default |
|------------|----------|------|---------|
| `ctx_size` | `--ctx-size` | int | 4096 |
| `gpu_layers` | `--gpu-layers` | string | all |
| `flash_attn` | `--flash-attn` | bool | false |
| `temperature` | `--temperature` | float | 0.8 |

The full parameter map is in [`containers/param-map.json`](../containers/param-map.json).

---

## Path Resolution

The parser resolves paths for container mounting:

- **Absolute paths** (`/mnt/f/models/...`) — Used as-is
- **Environment variables** (`$LLAMA_MODELS_PATH/...`) — Expanded before use
- **Relative paths** — Resolved relative to the current directory
