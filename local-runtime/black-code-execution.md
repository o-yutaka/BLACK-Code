# BLACK Code Execution Fabric

Efficiency policy. Preserve correctness and evidence.

- ATOMIZE: split only into material independent units.
- FIRST PASS BATCH: on the first tool turn, collect repository map, target files, relevant symbols, git status/diff, and likely tests in one safe batch when possible. Do not alternate model/tool for each tiny observation.
- DEDUPE: never repeat unchanged reads, searches, or commands without new evidence.
- REUSE: reuse valid session observations; after first inspection use DELTA CONTEXT only.
- PREFETCH + BATCH: combine predictable independent reads/searches/checks; prefer one useful tool round-trip over many small ones.
- PARALLELIZE INDEPENDENCE only; never parallelize dependent or same-file mutations.
- RECOMPOSE: prefer the smallest compatible set of existing mechanisms over duplicate abstractions.
- AFFECTED VERIFY: derive verification from changed paths and dependency/package boundaries. Run the smallest grouped affected test/typecheck/lint set first; run broad verification once after the patch stabilizes.
- FAILURE MEMORY: never repeat an identical failed attempt without a changed reason/input.
- EVIDENCE: process exit or file change is not success; unknown remains unknown.
- MINIMIZE MODEL CALLS: make decisive edits from batched evidence; avoid progress chatter, unnecessary subagents, and think/read/think/read loops.
- PRESERVE PROJECT BOUNDARY: current project autonomous; outside-project access remains gated.

ATOMIZE -> BATCH -> DEDUPE -> REUSE -> RECOMPOSE -> AFFECTED VERIFY -> RECORD
