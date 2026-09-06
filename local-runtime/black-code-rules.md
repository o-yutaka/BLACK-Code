# BLACK Code Execution Rules (canonical, read on demand)

Canonical policy: fastest verified completion, not fastest token emission.
Index path: INDEX -> RULES -> DELTA -> BATCH -> EDIT -> STRUCTURAL_OK -> RESOLVE -> AFFECTED_VERIFY -> FINAL_VERIFY -> HASH_BIND -> RECORD

## R1 NO_UNVERIFIED_SUCCESS
Never claim `PASS`, `WORKING`, `FIXED`, `COMPLETE`, `DONE`, or `VERIFIED` without a current hash-bound gate token. A later edit invalidates it.

## R2 VERIFY_AFTER_MUTATION
A successful edit is not verification. Syntax/parse checks are only `STRUCTURAL_OK`. After the final edit stabilizes, run `black-code-verify`; if the gate reports `BLOCKED`, rerun it with `-RuntimeCommand "<real task entrypoint/smoke command>"`. The runtime command must exercise the changed behavior and must not be a no-op.

## R3 INSPECT_BEFORE_EDIT
Workspace is authority. Before using an API, symbol, dependency, command, path, config key, CLI flag, or test target, confirm it from the real workspace or an authoritative source. Never invent one.

## R4 MAX_SAFE_EXECUTION
Only safe, task-relevant commands run autonomously. Destructive, heavy, or outside-project actions require approval. Current project is autonomous.

## R5 WINDOWS_NATIVE_RUNTIME
The model server and ALL BLACK runtime entrypoints invoke native Windows PowerShell and llama.exe (`-File` invocation only). Never run the runtime from inside WSL's PowerShell shim in a way that bypasses the native gate; the runtime host boundary is `native-windows-no-docker-no-wsl`.

## R6 WSL_CONTROLLER_ALLOWED
WSL may launch and supervise BLACK Code (controller role only). It must never substitute for the native Windows runtime gate or for final verification.

## R7 DOCKER_NOT_REQUIRED
Do not introduce Docker or container layers for running, serving, or verifying the runtime. Native binaries are required and sufficient.

## Operational rules
- INDEX FIRST: use `repo-context.md` capsule before rediscovering repository structure. Reuse unchanged HEAD/package/test facts; inspect only task-relevant or changed paths.
- PROJECT RULE BRIDGE: obey `project-rules.md`. It imports compatible `CLAUDE.md`, `CLAUDE.local.md`, `BLACK.md`, and non-fenced `@file` references without replacing current-user intent.
- ATOMIZE ONLY MATERIAL WORK: split independent work only when it reduces latency or ambiguity. Do not create ceremonial subagents.
- FIRST PASS BATCH: collect missing target files, symbols, git state, relevant dependencies, and likely tests together when independent.
- DEDUPE: never repeat unchanged reads, searches, or commands without new evidence.
- DELTA CONTEXT: after first inspection, retain only changed/newly relevant facts. Do not rebuild the repository map from scratch.
- PREFETCH + BATCH: prefer one useful tool round-trip over many small think/read/think/read loops.
- PARALLELIZE INDEPENDENCE ONLY: CPU-side reads/searches/indexing/checks may be parallel when independent. Model inference remains one active local slot; never parallelize dependent or same-file mutations.
- RECOMPOSE: use the smallest compatible set of existing mechanisms rather than duplicating abstractions.
- RESOLVE BEFORE CLAIMING: imports, packages, symbols, signatures, config keys, and runtime versions used by changed code must resolve in the actual environment or be exercised by a stronger project check.
- AFFECTED VERIFY: start with `repo-context.md` likely tests and changed package boundaries. Run the smallest grouped affected tests/typechecks/lints first.
- FAILURE MEMORY: never repeat an identical failed command against the same workspace state. Inspect the failure and change the cause, input, command, or strategy.
- EVIDENCE: process exit, file creation, patch success, syntax success, or model confidence is not task success. Unknown remains unknown.
- MINIMIZE MODEL CALLS: make decisive edits from batched evidence; avoid progress chatter and unnecessary model turns.
- TEXT/CODE ONLY: BLACK Code does not require a vision model. Do not add or load a vision sidecar for normal operation.
- PRESERVE PROJECT BOUNDARY: current project is autonomous; outside-project access remains gated.