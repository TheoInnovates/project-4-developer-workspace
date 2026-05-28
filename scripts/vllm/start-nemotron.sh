#!/bin/bash
set -e
echo "[nemotron] Serving ${NEMOTRON_SUPER_MODEL} on port 8001..."
exec vllm serve "${NEMOTRON_SUPER_MODEL}" \
    --host 0.0.0.0 \
    --port 8001 \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.53 \
    --max-model-len 90000 \
    --kv-cache-dtype fp8 \
    --enable-prefix-caching \
    --trust-remote-code \
    --enable-auto-tool-choice \
    --tool-call-parser llama3_json \
    --api-key "${VLLM_API_KEY}"
