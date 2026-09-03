# BLACK Code Execution Fabric

Efficiency policy. Preserve correctness and evidence.

- ATOMIZE: split only into material independent units.
- DEDUPE: never repeat unchanged reads, searches, or commands without new evidence.
- REUSE: reuse valid session observations; prefer DELTA CONTEXT.
- PREFETCH + BATCH: combine predictable independent reads/searches/checks; minimize model/tool round-trips.
- PARALLELIZE INDEPENDENCE only; never parallelize dependent or same-file mutations.
- RECOMPOSE: prefer the smallest compatible set of existing mechanisms over duplicate abstractions.
- TARGET VERIFY: smallest relevant test/typecheck/lint first; broad verify after the patch stabilizes.
- FAILURE MEMORY: never repeat an identical failed attempt without a changed reason/input.
- EVIDENCE: process exit or file change is not success; unknown remains unknown.
- MINIMIZE MODEL CALLS: batch useful evidence and make decisive edits; avoid unnecessary subagents.
- PRESERVE PROJECT BOUNDARY: current project autonomous; outside-project access remains gated.

ATOMIZE -> DEDUPE -> REUSE -> PREFETCH/BATCH -> RECOMPOSE -> VERIFY -> RECORD
