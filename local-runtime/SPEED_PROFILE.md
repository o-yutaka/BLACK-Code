# BLACK Code governed speed profile v4

Canonical objective: minimize **verified task latency**, not raw tokens/sec.

## Fixed canonical model

- main: `Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf`
- size gate: 7.20..7.35 GB decimal; target profile is 7.27 GB-class
- source: pinned JonathanColetti uncensored parent
- precision allocation: pinned Unsloth 7.27 reference tensor map
- imatrix: pinned uncensored imatrix
- main MTP tensors: excluded
- external draft: fixed uncensored Q4_0 MTP GGUF
- MTP draft max: 2
- local model parallel slots: 1
- repository-sized context on 12 GB GPUs: 16,384 floor (small/medium previously 8,192/12,288 did not fit the OpenCode system prompt; the auto tiers now clamp to 16,384)
- output cap coupled to context: 8,192
- KV K/V: q8_0 / q8_0
- `ngram-mod`: off
- forced `cache-reuse`: off
- thinking: off
- vision: off
- repo delta index: on
- governed final verification: on
- bottleneck telemetry: observation-only

## No IQ2_M fallback

The former 10.6 GB IQ2_M artifact is superseded. BLACK Code no longer treats it as the runtime baseline or an automatic recovery path. If the 7.27 canonical file is absent or invalid, setup rebuilds the fixed 7.27 model from its locked inputs instead of silently changing the model class.

## MTP2

MTP max2 remains the runtime default inherited from the prior measured BLACK Code profile, but it now uses the separate pinned uncensored Q4_0 draft because the main 7.27 model is built `--no-mtp`. Telemetry remains the authority for future speed changes; a larger draft width is not enabled merely because it exists.

## Auto context

Small repositories should not overpay KV/prefill cost, but the OpenCode system bundle itself needs more than the old 8K auto tier. The 12 GB canonical GPU auto context therefore has a 16,384 floor; <=150 and <=800 tracked files both clamp to 16,384, and larger/unknown repositories use 16,384 as well. RAM-tier machines keep 24,576 / 32,768. `-Context` remains an explicit override.

## Concurrency

The RTX 3060 12 GB path keeps one active 27B inference slot. Independent CPU-side indexing, hashing, reads, searches and checks may run concurrently. Hugging Face parent transfer uses high-performance Xet; standalone large files use up to 8 BLACK range workers by default.

## Governed completion

A fast invalid answer is a regression:

```text
STRUCTURAL_OK != VERIFIED
```

Canonical completion:

```text
INDEX -> RULES -> DELTA -> BATCH -> EDIT
      -> STRUCTURAL_OK -> RESOLVE
      -> AFFECTED_VERIFY -> FINAL_VERIFY
      -> HASH_BIND -> RECORD
```

The final verification must run after the final mutation. Any later edit invalidates the completion token.

## Rejected/superseded atoms

- IQ2_M canonical runtime: superseded by fixed BLACK 7.27
- IQ4_XS runtime: superseded
- MTP4 default: not promoted
- `ngram-mod`: rejected after agentic regression
- forced `cache-reuse`: rejected/unproven for canonical path
- parallel local 27B inference: rejected for 12 GB canonical hardware
- vision sidecar: removed
