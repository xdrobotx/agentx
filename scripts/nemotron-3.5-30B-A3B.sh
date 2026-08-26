#!/bin/bash

export CUDA_VISIBLE_DEVICES=0

llama-server \
    --model /e/llama.cpp/models/nemotron-3.5-lightning-30B-A3B/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-Q4_0.gguf \
    --host 0.0.0.0 \
    --port 9696 \
    --ctx-size 131072 \
    --parallel 1 \
    --threads 9 \
    --gpu-layers all \
    --cpu-moe \
    --cpu-moe-draft \
    --fit off \
    --flash-attn 1 \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --spec-type draft-mtp \
    --spec-draft-n-max 1 \
    --spec-draft-n-min 1 \
    --spec-draft-type-k q4_0 \
    --spec-draft-type-v q4_0 \
    --image-min-tokens 1024 \
    --cache-ram 1024 \
    --cache-prompt \
    --load-mode none \
    --temperature 0.69 \
    --top-p 0.95 \
    --top-k 40 \
    --min-p 0.01 \
    --repeat-penalty 1.0 \
    --presence-penalty 0.0 \
    --frequency-penalty 0.0 \
    --reasoning on \
    --reasoning-budget 2048 \
    --reasoning-preserve \
    --jinja \
    # --no-ui
