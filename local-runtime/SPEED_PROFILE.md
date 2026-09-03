# BLACK Code IQ2_M speed profile v2

Canonical speed/memory path:

- Qwen3.8-27B Uncensored IQ2_M (10.6 GB)
- MTP speculative decoding always on
- MTP draft max 2
- repository-sized context on 12 GB GPUs: 8,192 / 12,288 / 16,384
- output cap coupled to context: 4,096 / 6,144 / 8,192
- `ngram-mod` disabled
- forced `cache-reuse` disabled
- explicit tensor split disabled
- parallel slots = 1
- thinking disabled
- BLACK Execution Fabric agent policy enabled

Why IQ2_M: the published GGUF keeps the same 27B architecture and fused MTP head while reducing model size versus IQ4_XS. On a 12 GB-class GPU this reduces CPU/RAM spill pressure.

Why MTP2: the model publisher's IQ2_M code benchmark reports the best tested code-generation throughput at `draft-mtp n_max=2` among its tested widths, so BLACK Code uses MTP2 for the speed-first default.

Why auto context: small repositories do not need to pay the KV/prefill cost of the full 16K window. BLACK Code counts tracked files at launch: <=150 uses 8K, <=800 uses 12K, larger/unknown uses 16K on a 12 GB GPU. `-Context` still overrides this explicitly.

Why Execution Fabric v2: the first investigation round batches repository map, target files, relevant symbols, git state and likely tests where safe; subsequent work uses delta context. Verification is derived from changed paths and package/dependency boundaries before one broad final verification. This targets fewer model/tool alternations without weakening success evidence.

The previously combined `MTP + ngram-mod + cache-reuse` profile regressed observed agentic end-to-end runtime, so those atoms remain rejected. Explicit tensor split is also not used by the canonical Windows path.

Static validation asserts the IQ2_M filename/SHA, MTP2, auto-context thresholds, output caps, batching/affected-verification rules and absence of rejected speculative/cache/tensor-split flags. Task success still requires task-level verification.
