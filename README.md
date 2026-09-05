# BLACK Code

BLACK Code is the local coding-agent/runtime side of the BLACK ecosystem. It stays independent from BLACK itself and can later export verified coding knowledge/experience into BLACK's Code Knowledge capability.

## Canonical runtime

```text
OpenCode TUI
  -> repo delta index + project rules
  -> local Qwen3.8-27B Uncensored / llama.cpp CUDA
  -> project-local tools
  -> affected verification
  -> black-code-verify
  -> workspace-hash-bound completion governor
  -> telemetry / bottleneck / evidence
```

Canonical Windows hardware target: RTX 3060 12 GB / 32 GB RAM.

Current verified model baseline:

- **Qwen3.8-27B-Uncensored IQ2_M** (~10.6 GB)
- fused MTP, draft max 2
- local model parallel slots = 1
- auto context = 8K / 12K / 16K by repository size
- KV q8_0/q8_0
- thinking off
- vision off

The planned ~7.27 GB uncensored model remains a candidate until a real GGUF is built and passes the same code-quality, uncensored-regression, VRAM and verified-task-latency gates. BLACK Code does not fake-promote an unbuilt artifact.

## One-command use

First bootstrap:

```bat
BLACK-CODE.cmd
```

Normal use from any code repository:

```bat
black-code
```

Final task verification is available as:

```bat
black-code-verify
```

## Execution contract

```text
INDEX -> RULES -> DELTA -> BATCH -> EDIT
      -> STRUCTURAL_OK -> RESOLVE
      -> AFFECTED_VERIFY -> FINAL_VERIFY
      -> HASH_BIND -> RECORD
```

Syntax or patch success is never task success by itself. After the final edit, `black-code-verify` must produce strong project/runtime evidence. The completion governor binds that result to the current workspace fingerprint; a later edit invalidates it and prevents an unverified completion from being presented as finished.

The runtime also preserves unverified state across sessions and rejects an identical failed command against the same unchanged workspace state.

## Speed and download path

The canonical runtime retains MTP2, repo delta indexing, affected-test mapping, automatic context/VRAM fitting and observation-only bottleneck telemetry. Independent CPU-side work may be parallelized, while 27B model inference stays at one local slot.

Hugging Face model setup uses 8 concurrent HTTP range workers by default, verifies every chunk and joined size, then verifies the pinned GGUF SHA-256. It falls back to a resumable single-stream download if parallel range transfer is unavailable or fails.

## Claude-style donor compatibility

The older custom Python Claude-Code-style BLACK Code is not a second canonical execution runtime. Its useful capabilities are incorporated selectively: Claude/BLACK project-rule hierarchy, continuity of unfinished/unverified work, failure-repeat prevention, and evidence-gated completion.

OpenCode remains the TUI/tool runtime. Current OpenCode-native skill discovery is used rather than maintaining a duplicate BLACK Code skill loader.

See [`local-runtime/README.md`](local-runtime/README.md), [`local-runtime/SPEED_PROFILE.md`](local-runtime/SPEED_PROFILE.md), and [`local-runtime/CANONICAL_ARCHITECTURE.md`](local-runtime/CANONICAL_ARCHITECTURE.md).

## BLACK Sentinel — Codex Pet

`codex-pet/` remains a separate BLACK Code companion package; see [`codex-pet/README.md`](codex-pet/README.md).
