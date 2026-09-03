# BLACK Code Local Runtime

BLACK Code uses a single speed-first local coding runtime on Windows.

## Canonical model

- Repository: `JonathanColetti/Qwen3.8-27B-Uncensored-GGUF`
- File: `Qwen3.8-27B-Uncensored-IQ2_M.gguf`
- Published size: 10.6 GB
- SHA-256: `28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187`
- Embedded MTP: yes

The model is downloaded to `%LOCALAPPDATA%\BLACK-Code\runtime\models\` and is never committed to this repository. After IQ2_M verifies successfully, setup removes the superseded local IQ4_XS weight instead of retaining a second runtime profile.

## One command

First run from the repository:

```bat
BLACK-CODE.cmd
```

After setup, from any code repository:

```bat
black-code
```

## Speed profile

For RTX 3060 12 GB-class hardware the default is:

```text
Qwen3.8-27B IQ2_M
context              16,384
fit target headroom  1,024 MiB
parallel              1
MTP                   always on
MTP draft max         2
ngram-mod             off
forced cache-reuse    off
thinking              off
KV K/V                q8_0 / q8_0
```

The IQ2_M model publisher's measured coding prompt was fastest at MTP `n_max=2`, so BLACK Code uses that value rather than carrying over the previous IQ4_XS tuning.

## BLACK Execution Fabric

BLACK Code copies BLACK's execution design without importing or modifying the BLACK repository:

```text
ATOMIZE -> DEDUPE -> REUSE -> PREFETCH/BATCH -> RECOMPOSE -> VERIFY -> RECORD
```

The persistent OpenCode instructions reduce duplicate reads/searches, reuse unchanged observations, batch predictable independent work, parallelize only independent work, and verify the smallest relevant scope before broad verification.

Each session records a canonical profile hash, duration, project fingerprint, GPU/VRAM start state, exit code and llama.cpp log paths in:

```text
%LOCALAPPDATA%\BLACK-Code\runtime\execution-fabric\sessions.jsonl
```

Session evidence remains `UNVERIFIED` until task-level verification proves success.

## Runtime boundaries

- project-local editing and commands: autonomous
- outside-project access: approval gated
- server bind: `127.0.0.1` only
- `enable_thinking=false`
- no silent ngram/cache speculative fallback

## Refresh

Refresh launcher/config without forcing a model replacement:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\setup.ps1
```

Refresh llama.cpp only:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\setup.ps1 -ForceLlama
```

Full model/runtime refresh:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\setup.ps1 -Force
```

## Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\BLACK-Code\launcher\doctor.ps1"
```
