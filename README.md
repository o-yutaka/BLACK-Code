# BLACK Code

Self-evolving autonomous system with:

- Task generation
- Failure avoidance
- Score optimization loop

## Local coding runtime — Qwen3.8-27B Uncensored

BLACK Code's canonical Windows local coding runtime uses:

- **Qwen3.8-27B-Uncensored IQ2_M** (~10.6 GB)
- llama.cpp CUDA
- OpenCode as the coding-agent interface
- autonomous project-local editing and shell commands
- BLACK-derived execution optimization without importing or modifying BLACK itself

The model and runtime binaries live outside Git under `%LOCALAPPDATA%\BLACK-Code\runtime`.

### First run

```bat
BLACK-CODE.cmd
```

After bootstrap, open any repository and run:

```bat
black-code
```

### BLACK Execution Fabric

BLACK Code copies the design pattern from BLACK's atomization/recomposition/learning path into BLACK Code only:

```text
ATOMIZE -> DEDUPE -> REUSE -> PREFETCH/BATCH -> RECOMPOSE -> VERIFY -> RECORD
```

The speed-first runtime uses **IQ2_M + fused MTP max 2**. `ngram-mod` and forced `cache-reuse` remain off after measured agentic regressions. On 12 GB VRAM hardware the default context is **16,384** with about **1,024 MiB** fit headroom so more of the 10.6 GB model stays on GPU.

The previous IQ4_XS runtime is not retained as a selectable BLACK Code profile. Once IQ2_M passes SHA-256 verification, setup removes the superseded local IQ4_XS weight automatically.

A clean process exit remains `UNVERIFIED` until real task verification exists.

See [`local-runtime/README.md`](local-runtime/README.md) for runtime details and diagnostics.

## BLACK Sentinel — Codex Pet

`codex-pet/` contains the BLACK Code Codex V2 companion package. See [`codex-pet/README.md`](codex-pet/README.md) for details.
