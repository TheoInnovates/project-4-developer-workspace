#!/bin/bash
# Serve Nemotron 3 Super 120B-A12B NVFP4 on the spark-d5dd GB10.
# Flags follow NVIDIA's Spark deployment guide
# (NVIDIA-NeMo/Nemotron usage-cookbook/Nemotron-3-Super/SparkDeploymentGuide),
# adapted for co-tenancy with the dev stack:
#   - gpu-memory-utilization 0.72 (guide uses 0.90 on a dedicated Spark) so
#     GitLab & friends keep ~35GB of the 128GB unified memory
#   - max-model-len 262144 instead of 1M (matches the coder; KV at 0.72
#     holds ~690k tokens, so several long chats fit concurrently)
#   - MTP speculative decoding disabled: it needs a per-draft
#     --speculative_config '{"method":"mtp","num_speculative_tokens":3,"moe_backend":"triton"}'
#     (the MTP head is unquantized, so it can't use the marlin MoE backend),
#     and this container's vLLM rejects the moe_backend key. Revisit when the
#     nvcr vllm image catches up with the guide's cu130-nightly.
set -e

# Marlin GEMM is required for NVFP4 on the GB10 (other backends raise
# illegal-instruction); flashinfer FP4 MoE is Blackwell-multi-GPU only.
export VLLM_NVFP4_GEMM_BACKEND=marlin
export VLLM_FLASHINFER_ALLREDUCE_BACKEND=trtllm
export VLLM_USE_FLASHINFER_MOE_FP4=0

echo "[nemotron] Serving ${NEMOTRON_SUPER_MODEL} on port 8001..."
exec vllm serve "${NEMOTRON_SUPER_MODEL}" \
    --host 0.0.0.0 \
    --port 8001 \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.72 \
    --max-model-len 262144 \
    --max-num-seqs 4 \
    --kv-cache-dtype fp8 \
    --mamba_ssm_cache_dtype float32 \
    --quantization fp4 \
    --moe-backend marlin \
    --async-scheduling \
    --enable-chunked-prefill \
    --trust-remote-code \
    --reasoning-parser-plugin /workspace/super_v3_reasoning_parser.py \
    --reasoning-parser super_v3 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --api-key "${VLLM_API_KEY}"
