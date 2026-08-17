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
#     defaults to 'xhigh'. That is invisible latency, not free: measured here,
#     "is 91 prime?" burns ~140 reasoning tokens at ~8.3 tok/s. Suppress with
#     chat_template_kwargs={"enable_thinking": false} (verified: reasoning goes
#     to zero) or turn it down with reasoning_effort.
#
#     Two gotchas, both confirmed against this deployment:
#
#     a) reasoning_effort has two disagreeing validators. vLLM's request schema
#        checks OpenAI's enum (none|low|medium|high) and 400s on 'xhigh'; the
#        chat template accepts (xhigh|medium|low) and 400s on 'high'. Only
#        'low' and 'medium' pass both. 'xhigh' is selected by OMITTING the
#        field — the template defaults to it — never by naming it.
#
#     b) the reasoning text comes back in the message field `reasoning`, NOT
#        `reasoning_content`. Clients reading the latter see an empty string
#        and will wrongly conclude thinking is disabled.
#
#     The qwen3 reasoning parser works correctly, so content stays clean —
#     the super_v3 parser/enable_thinking pairing trap documented in
#     start-nemotron.sh does not apply here.
#
#   - MTP speculative decoding is ON. mtp.safetensors ships in the model repo
#     and vLLM registers Qwen3_5MTP, so no extra draft model is needed. This
#     is the main lever on decode speed: the measured baseline without it was
#     ~8.3 tok/s, which is bandwidth-bound rather than compute-bound, exactly
#     the regime speculative decoding exists for.
#
#     Unlike Nemotron — whose script documents MTP being unusable because its
#     unquantized MTP head could not share the marlin MoE backend — this model
#     is dense, so that conflict does not arise.
#
#     Measured on this host, greedy (temp 0), 400-token completions:
#
#       prompt type        baseline    MTP     speedup   draft acceptance
#       code-boilerplate    8.34      20.31     2.44x      92-98%
#       code-algorithm      8.34      21.75     2.61x      92-98%
#       structured-json     8.34      21.97     2.63x      92-98%
#       open-prose          8.33      16.16     1.94x      57-65%
#       mean                8.34      20.05     2.40x
#
#     The baseline is flat to 0.01 tok/s across all four — decode here is
#     bandwidth-bound, so content doesn't matter until speculation enters the
#     picture. All the post-MTP spread is acceptance rate.
#
#     num_speculative_tokens=3 follows the vLLM recipe and suits a coding
#     workload. Per-position acceptance shows why 3 is the right stopping
#     point for mixed use: code holds up at position 3 (0.877) while prose
#     collapses (0.312). If this host ever serves code exclusively, 4-5 is
#     worth testing; for mixed traffic the extra drafts would be wasted work.
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
    --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
    --api-key "${VLLM_API_KEY}"
