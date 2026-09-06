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

## Prompt Budget Governor

A fixed 16K floor was proven insufficient: an all-schema, verbose-rules first request measured 21,839 prompt tokens and was rejected at 16K. Instead of swallowing that into 32K, the governor reduces the first prompt and keeps the common context at 16K:

- Tiers `FAST` / `CODE` / `DEEP` (default by tracked file count, or `-Tier`) set a tool allowlist in the runtime config. Disabled tools drop out of the model request schema entirely (`tools.filter((t,i) => tools?.[i] !== false)`, verified in opencode-ai 1.18.28), so FAST keeps only stem coding tools and drops task/lsp/skill/websearch/webfetch.
- `repo-context.md` is a compact "Repo Capsule" (counts, HEAD, packages, top dirs, first 15 changed paths); details are read/grepped on demand instead of pre-injected.
- Execution rules are shipped as R1-R7 IDs in the boot prompt; the full canonical text lives in `black-code-rules.md` and is read on demand. `project-rules.md` is capped at 6,000 chars with source pointers.

Measured 2026-09-07 (empty repo, FAST): real first request = **7,842 prompt tokens** (was 21,839), `opencode run` answered fine on a 16K server. Targets hold: empty repo ≈ 7.8K, so ≤10K goal is met and 16K boots normally, leaving the freed context for actual coding reasoning and code.

## Auto context

Context is selected from the budgeted prompt estimate, not a fixed floor: per-tier fixed base (FAST 7,200 / CODE 9,200 / DEEP 12,500, calibrated from the 7,842 measurement) + measured injected instruction bytes + a 1,024 safety margin, rounded up to 16K/24K/32K/48K/64K and capped at 32,768 under 40 GiB RAM. FAST output is capped at 4,096 to leave prompt headroom; CODE/DEEP get 8,192. `-Context` remains an explicit override.

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
