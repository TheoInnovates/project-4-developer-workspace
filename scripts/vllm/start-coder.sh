#!/bin/bash
set -e
echo "[coder] Serving ${CODER_MAIN_MODEL} on port 8001..."
exec vllm serve "${CODER_MAIN_MODEL}" \
    --host 0.0.0.0 \
    --port 8001 \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.90 \
    --max-model-len 262144 \
    --kv-cache-dtype fp8 \
    --enable-prefix-caching \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml \
    --api-key "${VLLM_API_KEY}"
