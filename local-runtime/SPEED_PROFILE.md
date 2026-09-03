# BLACK Code IQ2_M speed profile

Canonical speed/memory path:

- Qwen3.8-27B Uncensored IQ2_M (10.6 GB)
- MTP speculative decoding always on
- MTP draft max 2
- `ngram-mod` disabled by default
- forced `cache-reuse` disabled by default
- parallel slots = 1
- thinking disabled
- BLACK Execution Fabric agent policy remains enabled

Why IQ2_M: the published GGUF keeps the same 27B architecture and fused MTP head while reducing the model from 15.3 GB IQ4_XS to 10.6 GB. On a 12 GB-class GPU this materially reduces CPU/RAM spill pressure.

Why MTP2: the model publisher's IQ2_M code benchmark reports the best tested code-generation throughput at `draft-mtp n_max=2` (1.32x its no-spec baseline), ahead of tested n_max 1 and 3. BLACK Code therefore uses MTP2 for the speed-first default instead of retaining MTP4 by assumption.

The previously combined `MTP + ngram-mod + cache-reuse` profile regressed observed agentic end-to-end runtime, so those extra atoms remain rejected by default.

Static validation asserts the IQ2_M filename/SHA, MTP2, and absence of rejected speculative/cache flags. This document records the runtime default only; task success still requires task-level verification.
