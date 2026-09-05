# BLACK Code Canonical Architecture v3

## Boundary

BLACK Code is the local coding runtime/source-testbed. BLACK is a separate system. Code Knowledge belongs on the BLACK side; BLACK Code may later export verified experience packets, but BLACK Code never imports or mutates BLACK as part of normal coding execution.

The older Python Claude-style BLACK Code is a donor/reference implementation, not a second production runtime.

## Canonical ownership

| Capability | Canonical owner | Decision |
| --- | --- | --- |
| terminal coding UI and tool execution | OpenCode | KEEP |
| local model serving | llama.cpp CUDA | KEEP |
| 27B uncensored model baseline | Qwen3.8-27B IQ2_M | KEEP until candidate promotion |
| local model inference concurrency | one slot | KEEP |
| speculative decoding | fused MTP max2 baseline | KEEP, re-benchmark per candidate |
| repository structure/delta | `repo-index.ps1` | KEEP |
| affected test hints | `repo-index.ps1` + agent policy | KEEP/strengthen |
| context/VRAM policy | `black-code.ps1` | KEEP |
| tool/model bottleneck telemetry | OpenCode telemetry + llama logs | KEEP |
| Claude/BLACK rule hierarchy | `rule-bridge.ps1` | PORT from donor |
| duplicate skill loader | none | DROP; use OpenCode native discovery |
| donor custom Python TUI | donor/reference only | DROP from canonical runtime |
| donor custom model router/server | donor/reference only | DROP from canonical runtime |
| syntax-only post-edit success | `STRUCTURAL_OK` only | DOWNGRADE; never final verification |
| final verification | `verification-gate.ps1` / `black-code-verify` | CANONICAL |
| final claim authority | `opencode-governor.js` | CANONICAL |
| unverified restart continuity | governor state | PORT from donor idea |
| identical failed retry guard | governor | PORT from donor idea |
| vision model/sidecar | none | DROP |
| external advisor | non-canonical optional research | OFF by default |
| Hugging Face model download | parallel range downloader + SHA | CANONICAL |

## Runtime state machine

```text
CLEAN/KNOWN
   |
   v
INDEX + RULES
   |
   v
INSPECT/BATCH
   |
   v
EDIT -----------------------------+
   |                               |
   v                               |
DIRTY                              |
   |                               |
   v                               |
STRUCTURAL_OK                      |
   |                               |
   v                               |
RESOLVE                            |
   |                               |
   v                               |
AFFECTED_VERIFY                    |
   |                               |
   v                               |
FINAL_VERIFY --fail--> REPAIR -----+
   |
   v
WORKSPACE_HASH + VERIFY_PROFILE
   |
   v
VERIFICATION_TOKEN
   |
   v
FINAL/RECORD
```

Any mutation after `FINAL_VERIFY` moves the workspace back to DIRTY and invalidates the token.

## Definition of usable code

For an implementation request, BLACK Code must not equate parseability with usability. The strongest relevant checks available should establish the material parts of:

```text
syntax/structure
AND real dependency/symbol resolution
AND build/type validity where applicable
AND affected tests/checks
AND requested entrypoint/runtime behavior when project checks are insufficient
```

If the repository has no strong standard verification path, `black-code-verify` returns BLOCKED until a real task-specific `-RuntimeCommand` is supplied. A no-op command cannot satisfy the gate.

## Completion authority

The model may propose that work is complete, but it has no authority to make that true. `opencode-governor.js` owns final-claim admission:

1. Compute a workspace fingerprint.
2. Observe successful `black-code-verify` against that state.
3. Bind a verification token to the workspace fingerprint and verification profile.
4. Permit final completion only while the current workspace still matches the token.
5. Persist an unverified marker across restarts when work changed without a current token.
6. Block identical failed shell retries against the exact same workspace fingerprint.

## Performance objective

Primary metric:

```text
verified task latency
```

Supporting metrics:

- first-pass verified rate
- invalid import/API rate
- tool-call validity
- retry count
- TTFT
- decode tokens/sec
- MTP acceptance/effect
- prompt/prefill time
- tool time
- verification time
- peak VRAM / spill

A higher tokens/sec configuration that creates more repair loops is a regression.

## Model promotion

### Baseline

`Qwen3.8-27B-Uncensored-IQ2_M.gguf`, pinned by SHA-256, remains the reference runtime.

### ~7.27 GB candidate

The target is deliberately recorded as a candidate slot rather than a fake canonical filename. Promotion requires an actual GGUF plus reproducible evidence for:

- uncensored behavior retained relative to the chosen parent
- coding quality within the accepted regression budget
- tool-use reliability
- first-pass verified rate
- verified task latency versus IQ2_M baseline
- MTP width retest rather than blindly inheriting max2
- RTX 3060 12 GB VRAM/spill behavior
- file hash recorded before installer promotion

Only after those gates pass should setup/doctor/model alias be changed to the 7.27 GB artifact.

## Download policy

Hugging Face model download defaults to 8 independent byte-range workers. Every part must match its expected byte length; the joined file must match the probed total length; the final model must still match the pinned GGUF SHA-256. Range failure or unsupported range semantics falls back to resumable sequential download.

Download parallelism changes transfer latency only. It never weakens integrity verification.
