# BLACK Code

Self-evolving autonomous system with:

- Task generation
- Failure avoidance
- Score optimization loop

## Local coding runtime — Qwen3.8-27B Uncensored IQ2_M

BLACK Code uses a Windows local coding path built around:

- **Qwen3.8-27B-Uncensored IQ2_M** (published size 10.6 GB)
- llama.cpp CUDA
- automatic VRAM fitting
- OpenCode as the coding-agent interface
- autonomous project-local editing and shell commands
- BLACK-derived execution optimization without importing or modifying BLACK itself

The canonical IQ2_M file SHA-256 is `28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187`. Model/runtime binaries live outside Git under `%LOCALAPPDATA%\BLACK-Code\runtime`.

### First run

```bat
BLACK-CODE.cmd
```

After bootstrap, open any repository and run:

```bat
black-code
```

The current speed-first profile for RTX 3060 12 GB-class hardware uses 16,384 context, 1,024 MiB fit headroom, MTP always on with draft max 2, one parallel slot, no `ngram-mod`, no forced `cache-reuse`, and `enable_thinking=false`.

The previous IQ4_XS runtime is superseded; BLACK Code does not keep it as a selectable test profile, and setup removes the old local IQ4_XS weight after IQ2_M verifies successfully.

### BLACK Execution Fabric

BLACK Code copies the design pattern from BLACK's atomization/recomposition/learning path into BLACK Code only:

```text
ATOMIZE -> DEDUPE -> REUSE -> PREFETCH/BATCH -> RECOMPOSE -> VERIFY -> RECORD
```

The agent avoids duplicate reads/searches, reuses unchanged observations, batches independent work, runs targeted verification before broad verification, and records canonical session evidence. A clean process exit remains `UNVERIFIED` until task-level verification exists.

See [`local-runtime/README.md`](local-runtime/README.md) for runtime details and diagnostics.

## BLACK Sentinel — Codex Pet

`codex-pet/` contains the BLACK Code Codex V2 companion package.

- Transparent PNG atlas: **1536 × 2288**
- Grid: **8 × 11 / 88 frames**
- State-specific signals for idle, work, waiting, review, and failure
- Safe Windows and macOS/Linux installers with SHA-256 verification
- Deterministic generator and GitHub Actions validation

See [`codex-pet/README.md`](codex-pet/README.md) for details.
