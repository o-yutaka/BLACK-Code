# BLACK Code Execution Fabric

Canonical policy: fastest verified completion, not fastest token emission.

- WORKSPACE IS AUTHORITY: before using an API, symbol, dependency, command, path, config key, CLI flag, or test target, confirm it from the real workspace or an authoritative source. Never invent one.
- INDEX FIRST: use `repo-context.md` before rediscovering repository structure. Reuse unchanged HEAD/package/test facts; inspect only task-relevant or changed paths.
- PROJECT RULE BRIDGE: obey `project-rules.md`. It imports compatible `CLAUDE.md`, `CLAUDE.local.md`, `BLACK.md`, and non-fenced `@file` references without replacing current-user intent.
- ATOMIZE ONLY MATERIAL WORK: split independent work only when it reduces latency or ambiguity. Do not create ceremonial subagents.
- FIRST PASS BATCH: collect missing target files, symbols, git state, relevant dependencies, and likely tests together when independent.
- DEDUPE: never repeat unchanged reads, searches, or commands without new evidence.
- DELTA CONTEXT: after first inspection, retain only changed/newly relevant facts. Do not rebuild the repository map from scratch.
- PREFETCH + BATCH: prefer one useful tool round-trip over many small think/read/think/read loops.
- PARALLELIZE INDEPENDENCE ONLY: CPU-side reads/searches/indexing/checks may be parallel when independent. Model inference remains one active local slot; never parallelize dependent or same-file mutations.
- RECOMPOSE: use the smallest compatible set of existing mechanisms rather than duplicating abstractions.
- EDITS CREATE DIRTY STATE: a successful edit is not verification. Syntax/parse checks are only `STRUCTURAL_OK`; they are never `VERIFIED` by themselves.
- RESOLVE BEFORE CLAIMING: imports, packages, symbols, signatures, config keys, and runtime versions used by changed code must resolve in the actual environment or be exercised by a stronger project check.
- AFFECTED VERIFY: start with `repo-context.md` likely tests and changed package boundaries. Run the smallest grouped affected tests/typechecks/lints first.
- FINAL VERIFY: after the final edit stabilizes, run `black-code-verify`. If the gate reports `BLOCKED`, rerun it with `-RuntimeCommand "<real task entrypoint/smoke command>"`; the runtime command must exercise the changed behavior and must not be a no-op.
- HASH-BOUND COMPLETION: BLACK Code's governor binds final verification to the current workspace fingerprint. Any later edit invalidates it. Never claim `PASS`, `WORKING`, `FIXED`, `COMPLETE`, `DONE`, or `VERIFIED` without a valid current token.
- FAILURE MEMORY: never repeat an identical failed command against the same workspace state. Inspect the failure and change the cause, input, command, or strategy.
- EVIDENCE: process exit, file creation, patch success, syntax success, or model confidence is not task success. Unknown remains unknown.
- MINIMIZE MODEL CALLS: make decisive edits from batched evidence; avoid progress chatter and unnecessary model turns.
- TEXT/CODE ONLY: BLACK Code does not require a vision model. Do not add or load a vision sidecar for normal operation.
- PRESERVE PROJECT BOUNDARY: current project is autonomous; outside-project access remains gated.

Canonical path:

`INDEX -> RULES -> DELTA -> BATCH -> EDIT -> STRUCTURAL_OK -> RESOLVE -> AFFECTED_VERIFY -> FINAL_VERIFY -> HASH_BIND -> RECORD`
