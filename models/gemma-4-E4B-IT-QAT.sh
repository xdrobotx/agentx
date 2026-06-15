#!/bin/bash

export CUDA_VISIBLE_DEVICES=1

llama-server \
    --model /e/ai/.models/gemma-4-E4B-IT-QAT/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf \
    --mmproj /e/ai/.models/gemma-4-E4B-IT-QAT/mmproj-gemma-4-E4B-F16.gguf \
    --host 0.0.0.0 \
    --port 6969 \
    --ctx-size 32768 \
    --predict 8192 \
    --batch-size 4096 \
    --ubatch-size 512 \
    --parallel 1 \
    --threads 9 \
    --gpu-layers all \
    --temperature 0.6 \
    --top-p 0.95 \
    --top-k 40 \
    --min-p 0.01 \
    --repeat-penalty 1.0 \
    --presence-penalty 0.0 \
    --frequency-penalty 0.0 \
    --reasoning on \
    --reasoning-budget 2048 \
    --fit off \
    --flash-attn 1 \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --no-mmap \
    # --no-ui
