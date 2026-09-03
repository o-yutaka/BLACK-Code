# BLACK Code measured-fast profile

Canonical fast path:

- Qwen3.8-27B Uncensored IQ4_XS
- MTP speculative decoding always on
- MTP draft max 4
- `ngram-mod` disabled by default
- forced `cache-reuse` disabled by default
- parallel slots = 1
- thinking disabled
- BLACK Execution Fabric agent policy remains enabled

Reason: the combined `MTP + ngram-mod + cache-reuse` profile regressed end-to-end runtime in observed agentic work. BLACK Code therefore keeps the BLACK principle of measured selection: remove atoms that regress the measured path instead of keeping features merely because they exist.

Static validation also asserts that rejected speculative/cache flags cannot silently return to the default launcher.

This document records the default only. It does not claim a task is verified or successful.
