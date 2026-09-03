# BLACK Code Execution Fabric

Efficiency policy. Preserve correctness and evidence.

- INDEX FIRST: use `repo-context.md` before rediscovering repository structure. Treat its unchanged HEAD/package/test map as reusable evidence; inspect only task-relevant or changed paths.
- ATOMIZE: split only into material independent units.
- FIRST PASS BATCH: on the first tool turn, collect only missing target files/symbols plus git details not already present in the repo index. Batch predictable independent reads/checks.
- DEDUPE: never repeat unchanged reads, searches, or commands without new evidence.
- DELTA CONTEXT: after first inspection, keep only changed/newly relevant facts. Do not rebuild the repo map from scratch.
- PREFETCH + BATCH: prefer one useful tool round-trip over many small ones.
- PARALLELIZE INDEPENDENCE only; never parallelize dependent or same-file mutations.
- RECOMPOSE: prefer the smallest compatible set of existing mechanisms over duplicate abstractions.
- AFFECTED VERIFY: start with `repo-context.md` likely tests and changed package boundaries. Run the smallest grouped affected test/typecheck/lint set first; broad verification once after the patch stabilizes.
- FAILURE MEMORY: never repeat an identical failed attempt without a changed reason/input.
- EVIDENCE: process exit or file change is not success; unknown remains unknown.
- MINIMIZE MODEL CALLS: make decisive edits from batched evidence; avoid progress chatter, unnecessary subagents, and think/read/think/read loops.
- PRESERVE PROJECT BOUNDARY: current project autonomous; outside-project access remains gated.

INDEX -> DELTA -> BATCH -> DEDUPE -> RECOMPOSE -> AFFECTED VERIFY -> RECORD
