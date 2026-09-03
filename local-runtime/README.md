# BLACK Code Local Runtime

This directory contains BLACK Code's canonical Windows local coding runtime.

## Canonical model

- Repository: `JonathanColetti/Qwen3.8-27B-Uncensored-GGUF`
- File: `Qwen3.8-27B-Uncensored-IQ2_M.gguf`
- Published size: about 10.6 GB
- SHA-256: `28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187`
- MTP: fused / included

The model is downloaded to `%LOCALAPPDATA%\BLACK-Code\runtime\models\` and is never committed to Git.

## One-command use

First run:

```bat
BLACK-CODE.cmd
```

After bootstrap:

```bat
black-code
```

## Speed-first runtime

For RTX 3060 12 GB-class hardware BLACK Code uses:

```text
model                 IQ2_M 10.6 GB
context               auto: 8K / 12K / 16K by repo size
output cap            auto: 4K / 6K / 8K
fit target headroom   1,024 MiB
parallel slots        1
MTP                    always on
MTP draft max          2
ngram-mod              off
forced cache-reuse     off
explicit tensor split off
KV K/V                 q8_0 / q8_0
thinking               off
```

On a 12 GB GPU, tracked-file count selects context automatically: <=150 files uses 8,192; <=800 uses 12,288; larger or unknown repositories use 16,384. An explicit `black-code -Context <size>` overrides this policy.

The model publisher's IQ2_M code benchmark reports the best tested code-generation throughput at MTP `n_max=2`, so BLACK Code uses that value rather than carrying the old IQ4_XS/MTP4 tuning forward.

The previous IQ4_XS runtime/test profile is not retained. Setup first downloads and SHA-256 verifies IQ2_M; only after that succeeds does it delete an old local `Qwen3.8-27B-Uncensored-IQ4_XS.gguf` file.

## BLACK Execution Fabric

BLACK Code applies the execution design used by BLACK without importing or modifying BLACK itself:

```text
ATOMIZE -> BATCH -> DEDUPE -> REUSE -> RECOMPOSE -> AFFECTED VERIFY -> RECORD
```

The persistent OpenCode rules make the first safe investigation round collect repository map, target files, relevant symbols, git state/diff and likely tests together when possible. Later rounds use delta context instead of rereading unchanged material. Independent reads/searches/checks are batched, unnecessary subagents/progress chatter are avoided, and verification starts with affected tests/typechecks/lints derived from changed paths before one broad final verification.

Every session records a canonical execution-profile hash plus duration, project fingerprint, GPU/VRAM start state, exit code and log paths under:

```text
%LOCALAPPDATA%\BLACK-Code\runtime\execution-fabric\sessions.jsonl
```

A process exit remains `UNVERIFIED`; task success still requires task-level verification evidence.

## Setup refresh

Normal setup updates the launcher and downloads IQ2_M only if it is missing or invalid:

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

The server binds only to `127.0.0.1`; outside-project access remains approval-gated.
