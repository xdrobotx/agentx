#!/bin/bash

export CUDA_VISIBLE_DEVICES=0

llama-server \
    --model /e/agentx/models/qwen-3.6-35B-A3B-MTP/Qwen3.6-35B-A3B-UD-IQ4_NL.gguf \
    --mmproj /e/agentx/models/qwen-3.6-35B-A3B-MTP/mmproj-Qwen3.6-35B-A3B-F16.gguf \
    --host 0.0.0.0 \
    --port 9696 \
    --ctx-size 65536 \
    --predict 8192 \
    --batch-size 4096 \
    --ubatch-size 512 \
    --parallel 1 \
    --threads 9 \
    --gpu-layers all \
    --cpu-moe \
    --cpu-moe-draft \
    --fit off \
    --flash-attn 1 \
    --cache-type-k iq4_nl \
    --cache-type-v iq4_nl \
    --spec-type draft-mtp \
    --spec-draft-n-max 1 \
    --spec-draft-n-min 1 \
    --spec-draft-type-k iq4_nl \
    --spec-draft-type-v iq4_nl \
    --image-min-tokens 1024 \
    --cache-ram 1024 \
    --cache-prompt \
    --no-mmap \
    --temperature 0.6 \
    --top-p 0.95 \
    --top-k 40 \
    --min-p 0.01 \
    --repeat-penalty 1.0 \
    --presence-penalty 0.0 \
    --frequency-penalty 0.0 \
    --reasoning on \
    --reasoning-budget 2048 \
    --chat-template-kwargs '{"preserve_thinking":true}' \
    --jinja \
    # --no-ui
