# BLACK Code IQ2_M fast profile

Canonical runtime:

- Qwen3.8-27B Uncensored IQ2_M (10.6 GB)
- SHA256 `28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187`
- embedded MTP speculative decoding always on
- MTP draft max 2 for coding
- `ngram-mod` off
- forced `cache-reuse` off
- parallel slots = 1
- RTX 3060 12 GB default context = 16,384
- fit target headroom = 1,024 MiB
- thinking disabled
- BLACK Execution Fabric remains enabled

The previous IQ4_XS runtime and its temporary test profile are superseded and are not kept as a selectable BLACK Code runtime. Setup removes the old IQ4_XS weight after IQ2_M verifies successfully.

Reason: BLACK Code prioritizes end-to-end coding latency and VRAM residency. The published IQ2_M benchmark for this model shows the coding prompt fastest at MTP `n_max=2`; BLACK Code uses that as the default while retaining task-level evidence instead of claiming unmeasured success.
