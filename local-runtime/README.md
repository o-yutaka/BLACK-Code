# BLACK Code Local Runtime

This directory is the canonical Windows local coding runtime for BLACK Code.

## Canonical architecture

```text
OpenCode TUI
  -> BLACK execution instructions + repo delta context + Claude/BLACK rule bridge
  -> Qwen3.8-27B Uncensored through llama.cpp CUDA
  -> project-local tools
  -> affected verification
  -> black-code-verify final gate
  -> workspace-hash-bound completion governor
  -> telemetry / bottleneck / session evidence
```

The older Python Claude-style runtime is not a second canonical runtime. Its useful ideas are treated as donor capabilities: compatible rule hierarchy, continuity of unverified state, identical-failure repeat prevention, and evidence-gated completion. Execution remains OpenCode + llama.cpp so BLACK Code keeps one real runtime rather than two diverging agents.

BLACK itself is not imported or modified. BLACK Code remains the source/testbed side; only verified knowledge/experience may be bridged into BLACK's Code Knowledge capability later.

## Model policy

Verified baseline:

- Repository: `JonathanColetti/Qwen3.8-27B-Uncensored-GGUF`
- File: `Qwen3.8-27B-Uncensored-IQ2_M.gguf`
- Published size: about 10.6 GB
- SHA-256: `28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187`
- MTP: fused / included

The planned ~7.27 GB uncensored build is a **candidate**, not a claimed artifact. It is not promoted until the actual GGUF exists and passes the same runtime, coding, uncensored-regression, VRAM, and verified-task-latency gates. Until then the 10.6 GB IQ2_M file remains the reproducible baseline.

Vision is not part of the canonical runtime and no vision sidecar is loaded.

## One-command use

First run:

```bat
BLACK-CODE.cmd
```

After bootstrap:

```bat
black-code
```

The final verification command installed beside it is:

```bat
black-code-verify
```

For a project without a sufficiently strong standard verify/test/build path, exercise the changed behavior explicitly:

```bat
black-code-verify -RuntimeCommand "<real entrypoint or smoke command>"
```

No-op runtime commands are rejected.

## RTX 3060 12 GB speed baseline

```text
model                 IQ2_M 10.6 GB verified baseline
context               auto: 8K / 12K / 16K by tracked-file count
output cap            auto: 4K / 6K / 8K
fit target headroom   1,024 MiB
parallel model slots  1
MTP                    always on
MTP draft max          2
ngram-mod              off
forced cache-reuse     off
explicit tensor split off
KV K/V                 q8_0 / q8_0
thinking               off
vision                 off
```

Independent CPU-side reads, indexing, hashing and checks may be parallelized. Local 27B model inference remains one active slot on the 12 GB GPU.

## Hugging Face download

The model download uses `hf-parallel-download.ps1` with **8 range workers by default**. It probes HTTP range support, downloads byte ranges concurrently, validates every chunk size, concatenates in order, then the setup performs the canonical GGUF SHA-256 check. If the endpoint does not support range transfer or a parallel chunk fails, setup falls back to the resumable single-stream path instead of accepting a partial model.

Override setup concurrency when needed:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\setup.ps1 -HfDownloadWorkers 12
```

## Execution and verification

Canonical path:

```text
INDEX -> RULES -> DELTA -> BATCH -> EDIT
      -> STRUCTURAL_OK -> RESOLVE
      -> AFFECTED_VERIFY -> FINAL_VERIFY
      -> HASH_BIND -> RECORD
```

`STRUCTURAL_OK` means only that changed material parses at the relevant structural level. It is not completion evidence. `black-code-verify` selects the strongest standard project checks it can find (for example Node verify/test/build, Python pytest, Cargo test, Go test, or dotnet test). When no strong standard path exists it returns `BLOCKED` and requires a real task-specific runtime command.

`opencode-governor.js` binds successful final verification to the current workspace fingerprint. Later edits invalidate the token. If the model tries to emit a final completion after an unverified change, the generated completion is replaced with `BLACK VERIFY: UNVERIFIED` instead of being presented as finished work.

The governor also persists unverified continuity across BLACK Code sessions and blocks an identical failed shell command from being retried against the exact same workspace state.

## Context and repository delta

`repo-index.ps1` persists HEAD, changed files, package roots, test files, and likely affected tests. Clean same-HEAD sessions reuse the index; changed HEAD/worktree state gets a delta refresh rather than a full rediscovery.

`rule-bridge.ps1` imports compatible project guidance from:

- `~/.claude/CLAUDE.md`
- ancestor/project `CLAUDE.md`
- ancestor/project `CLAUDE.local.md`
- project `BLACK.md`
- non-fenced `@file` references, recursively up to depth 5

OpenCode natively discovers project/global `.claude/skills`, `.agents/skills`, and `.opencode/skills`, so BLACK Code does not maintain a duplicate skill loader.

## Evidence and bottlenecks

OpenCode tool timings and llama.cpp prompt/decode timings remain observation-only. Sessions record execution-profile hash, duration, project identity, GPU/VRAM start state, exit code and log paths under `%LOCALAPPDATA%\BLACK-Code\runtime\execution-fabric\sessions.jsonl`.

Process exit alone is not task verification. Final task verification is governed separately by the hash-bound gate.

## Setup refresh

Normal setup refreshes launch files and downloads the baseline model only if missing or invalid:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\setup.ps1
```

Refresh llama.cpp without forcing a model download:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\setup.ps1 -ForceLlama
```

Full refresh:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\setup.ps1 -Force
```

## Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\BLACK-Code\launcher\doctor.ps1"
```

The model server binds only to `127.0.0.1`; outside-project access remains approval-gated.
