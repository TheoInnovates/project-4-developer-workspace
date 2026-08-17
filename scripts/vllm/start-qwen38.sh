#!/bin/bash
# Serve Qwen3.8-27B-FP8 on the spark-d5dd GB10 — replaces Nemotron 3 Super.
# Flags follow the official vLLM recipe (recipes.vllm.ai/Qwen/Qwen3.8-27B),
# adapted for co-tenancy with imagefactory + debt-advisor:
#
#   - gpu-memory-utilization 0.85, not Nemotron's 0.72. That 0.72 reserved
#     ~35GB for GitLab & friends, which now live on the devhub VM on pve1;
#     only imagefactory + debt-advisor remain (~8GB). 0.85 is ~103GB, and it
#     stays under 0.90 because imagefactory's Packer/qemu builds spike RAM.
#
#   - max-model-len 262144 is the native window. The model card documents a
#     1M extension via a static-YaRN --hf-overrides block, but static YaRN
#     scales regardless of input length and degrades short prompts — don't
#     enable it unless a workload actually needs >262k.
#
#   - KV is cheap on this architecture. The hidden layout is
#     16 x (3 x (Gated DeltaNet -> FFN) -> 1 x (Gated Attention -> FFN)),
#     so only 1 layer in 4 holds a real KV cache; 262k fits with room to spare
#     even at 0.85. (This is why a 27B *dense* model still gets Nemotron-class
#     context here.)
#
#   - NO --kv-cache-dtype fp8, despite the vLLM recipe recommending it. This
#     checkpoint ships no k/v_scale scaling factors, so vLLM falls back to a
#     scale of 1.0 and warns about accuracy loss:
#       "Using KV cache scaling factor 1.0 for fp8_e4m3 ... verify that
#        k/v_scale scaling factors are properly set in the checkpoint"
#     Per the point above, KV is not the scarce resource here — trading a
#     quantization accuracy risk for memory we aren't short of is a bad deal.
#     Revisit if a calibrated FP8 checkpoint ships, or if KV ever binds.
#
#   - No --max-num-seqs cap. Nemotron's `4` was co-tenancy throttling for the
#     dev stack that no longer runs on this host.
#
#   - Thinking is ON, which is the model's default, and reasoning_effort
#     defaults to 'xhigh'. At this model's decode speed that is expensive for
#     interactive use. Tune per request with reasoning_effort='low'|'medium'
#     or chat_template_kwargs={"enable_thinking": false}; set a server-wide
#     default here only once the interactive cost has been measured.
#     Unlike Nemotron, this model ships a working reasoning parser (qwen3),
#     so reasoning_content is split from content properly rather than the
#     parser swallowing the whole answer — the super_v3 pairing trap in
#     start-nemotron.sh does not apply here.
#
#   - MTP speculative decoding is the next lever on decode speed:
#     mtp.safetensors ships in the repo, vLLM registers Qwen3_5MTP, and the
#     recipe quotes 0.77-0.90 acceptance. Add once baseline tok/s is known:
#       --speculative-config '{"method":"mtp","num_speculative_tokens":3}'
#     Left off for the first boot so the baseline is actually measurable.
set -e

echo "[qwen38] Serving ${QWEN38_MODEL} on port ${QWEN38_PORT:-8001}..."
exec vllm serve "${QWEN38_MODEL}" \
    --host 0.0.0.0 \
    --port "${QWEN38_PORT:-8001}" \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.85 \
    --max-model-len 262144 \
    --reasoning-parser qwen3 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --api-key "${VLLM_API_KEY}"
