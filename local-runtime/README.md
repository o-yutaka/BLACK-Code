# BLACK Code Local Runtime

This directory integrates BLACK Code with a local coding model on Windows.

## Default model

- Repository: `JonathanColetti/Qwen3.8-27B-Uncensored-GGUF`
- File: `Qwen3.8-27B-Uncensored-IQ4_XS.gguf`
- Size: about 15.3 GB
- SHA-256: `53adc4bbed67044d662273356bbf3a50fdec667ac21bbf18d13e5815fbccc7f5`

The model is **not** committed to this repository. It is downloaded into:

```text
%LOCALAPPDATA%\BLACK-Code\runtime\models\
```

llama.cpp, logs, execution-fabric evidence, and generated OpenCode runtime configuration are kept under the same `%LOCALAPPDATA%\BLACK-Code` tree.

## One-command use

From a fresh clone on Windows:

```bat
BLACK-CODE.cmd
```

The first run bootstraps missing dependencies, downloads and verifies the model, starts the local llama.cpp OpenAI-compatible server, then launches OpenCode in the current repository.

After bootstrap, `black-code` is added to the user PATH. From any code repository:

```bat
black-code
```

## BLACK Execution Fabric

BLACK Code now applies the execution design used by BLACK without importing or modifying the BLACK repository itself. The local runtime treats coding work as composable execution atoms:

```text
ATOMIZE -> DEDUPE -> REUSE -> PREFETCH/BATCH -> RECOMPOSE -> VERIFY -> RECORD
```

The generated OpenCode configuration injects `black-code-execution.md` as persistent session instructions. The agent is instructed to avoid duplicate reads/searches, reuse unchanged observations, batch predictable independent tool work, parallelize only genuinely independent work, and run targeted verification before broad verification.

Every local session also records a canonical execution-profile hash plus process duration, project fingerprint, GPU/VRAM start state, exit code and log paths under:

```text
%LOCALAPPDATA%\BLACK-Code\runtime\execution-fabric\sessions.jsonl
```

A process exit is deliberately recorded as `UNVERIFIED`; BLACK Code does not convert a clean exit into a success claim without task-level verification evidence.

## Autonomous project editing

The generated OpenCode configuration allows project-local:

- read
- create/write/edit/patch
- shell commands
- build/test/lint/install commands
- git commands through the shell
- search/LSP/skills
- subagents/tasks

`external_directory` remains `ask`, so a session opened in one repository does not silently modify unrelated directories.

## Memory policy

The launcher does not hard-code a GPU-layer count. It uses llama.cpp `--fit on` and `--fit-target` to use the available NVIDIA VRAM while retaining headroom for Windows and the display stack. On systems with 12 GB VRAM or less, the target headroom is 1536 MiB.

For a 32 GB RAM-class machine, the default context is 24,576 tokens. Override it with:

```bat
black-code -Context 16384
black-code -Context 32768
```

The KV cache uses `q8_0` for both K and V.

## Speculative decoding and prompt reuse

The accelerated profile is permanently enabled for the Qwen3.8 local runtime. Every `black-code` server session starts llama.cpp with:

```text
--spec-type draft-mtp,ngram-mod
--spec-draft-n-max 4
--spec-draft-n-min 0
--spec-draft-p-min 0.0
--spec-ngram-mod-n-match 24
--spec-ngram-mod-n-min 24
--spec-ngram-mod-n-max 64
--cache-reuse 256
```

MTP predicts from Qwen3.8's embedded MTP heads while `ngram-mod` adds a lightweight repetition-aware speculative path that is useful for repeated code/text. `--cache-reuse 256` keeps recurring prompt prefixes reusable inside the server process. There is no normal BLACK Code fallback that silently disables MTP.

## Setup refresh without model re-download

`setup.ps1 -ForceLlama` refreshes only the llama.cpp CUDA runtime. It does **not** force a re-download of the 15 GB GGUF. `-Force` remains the full refresh path.

## Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\BLACK-Code\launcher\doctor.ps1"
```

## Runtime boundaries

The local model server binds only to `127.0.0.1`. Qwen long-form thinking remains disabled by default through `enable_thinking=false`; this is independent from speculative decoding, which remains enabled.
