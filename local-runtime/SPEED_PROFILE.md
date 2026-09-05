# BLACK Code governed speed profile v3

Canonical objective: minimize **verified task latency**, not raw token latency.

## Verified baseline

- model: Qwen3.8-27B Uncensored IQ2_M (~10.6 GB)
- MTP speculative decoding: on
- MTP draft max: 2
- local model parallel slots: 1
- repository-sized context on 12 GB GPUs: 8,192 / 12,288 / 16,384
- output cap coupled to context: 4,096 / 6,144 / 8,192
- KV K/V: q8_0 / q8_0
- `ngram-mod`: off
- forced `cache-reuse`: off
- explicit tensor split: off
- thinking: off
- vision sidecar: off
- repo delta index: on
- governed final verification: on
- bottleneck telemetry: observation-only

## Why the 10.6 GB baseline stays

The existing IQ2_M GGUF has a pinned SHA-256 and known runtime contract. The planned ~7.27 GB uncensored build remains a candidate until the actual GGUF exists and beats or acceptably matches this baseline on coding quality, uncensored-regression, tool reliability, VRAM and end-to-end verified task latency. BLACK Code never promotes a filename or size target as if it were a verified artifact.

## Why MTP2 stays

The current IQ2_M code benchmark used for BLACK Code's prior tuning favored `draft-mtp n_max=2` among the tested widths. MTP4 is therefore superseded history rather than the current default. Any future 7.27 GB candidate must re-run the same measured comparison instead of inheriting MTP2 by assumption.

## Why auto context stays

Small repositories should not pay full KV/prefill cost. BLACK Code counts tracked files at launch: <=150 uses 8K, <=800 uses 12K, larger/unknown repositories use 16K on a 12 GB GPU. `-Context` remains an explicit override.

## Model and CPU concurrency

The RTX 3060 12 GB canonical path keeps one active 27B inference slot. Independent CPU-side indexing, hashing, reads, searches, checks and Hugging Face byte-range downloads may run concurrently when dependency-safe.

Hugging Face model setup defaults to 8 concurrent HTTP range workers, validates every range and the joined byte count, then performs the pinned GGUF SHA-256 verification. Unsupported/failed range mode falls back to resumable single-stream download.

## Governed completion

A fast invalid answer is a regression. The runtime distinguishes:

```text
STRUCTURAL_OK != VERIFIED
```

The canonical completion path is:

```text
INDEX -> RULES -> DELTA -> BATCH -> EDIT
      -> STRUCTURAL_OK -> RESOLVE
      -> AFFECTED_VERIFY -> FINAL_VERIFY
      -> HASH_BIND -> RECORD
```

`black-code-verify` must pass after the final edit. The completion governor binds that success to the current workspace fingerprint, and any later edit invalidates it. Repeating an identical failed command against the same workspace state is rejected.

## Rejected/superseded atoms

- IQ4_XS runtime profile: superseded by IQ2_M baseline
- MTP4 on IQ2_M: superseded by measured MTP2 baseline
- `ngram-mod`: rejected after agentic regression
- forced `cache-reuse`: rejected/unproven for the canonical path
- explicit tensor split: not canonical
- parallel local 27B inference: rejected for 12 GB canonical hardware
- vision sidecar: removed from the text/code canonical runtime

Static and executable runtime verification must keep these contracts distinct from future candidate experimentation.
