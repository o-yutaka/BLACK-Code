# BLACK Code Local Runtime

This directory integrates BLACK Code with a local coding model on Windows.

## Default model

- Repository: `JonathanColetti/Qwen3.8-27B-Uncensored-GGUF`
- File: `Qwen3.8-27B-Uncensored-IQ2_M.gguf`
- Size: about 10.6 GB
- SHA-256: `28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187`
- MTP: fused / included

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

BLACK Code applies the execution design used by BLACK without importing or modifying the BLACK repository itself. The local runtime treats coding work as composable execution atoms:

```text
ATOMIZE -> DEDUPE -> REUSE -> PREFETCH/BATCH -> RECOMPOSE -> VERIFY -> RECORD
```

The generated OpenCode configuration injects `black-code-execution.md` as persistent session instructions. The agent is instructed to avoid duplicate reads/searches, reuse unchanged observations, batch predictable independent tool work, parallelize only genuinely independent work, and run targeted verification before broad verification.

Every local session records a canonical execution-profile hash plus process duration, project fingerprint, GPU/VRAM start state, exit code and log paths under:

```text
%LOCALAPPDATA%\BLACK-Code\runtime\execution-fabric\sessions.jsonl
```

A process exit is deliberately recorded as `UNVERIFIED`; BLACK Code does not convert a clean exit into a success claim without task-level verification evidence.

## Autonomous project editing

The generated OpenCode configuration allows project-local read/edit/shell/build/test/lint/install/git/search/LSP/skills/subagent operations. `external_directory` remains `ask`, so a session opened in one repository does not silently modify unrelated directories.

## Memory policy

The launcher does not hard-code a GPU-layer count. It uses llama.cpp `--fit on` and `--fit-target` to use the available NVIDIA VRAM while retaining headroom for Windows and the display stack.

The speed-first IQ2_M model is about 10.6 GB instead of the previous 15.3 GB IQ4_XS. For a 12 GB GPU profile BLACK Code targets about 1024 MiB of free VRAM, allowing substantially more of the 27B model to remain on GPU while preserving operating headroom.

For a 32 GB RAM-class machine, the default context is 24,576 tokens. Override it with:

```bat
black-code -Context 16384
black-code -Context 32768
```

The KV cache uses `q8_0` for both K and V.

## Speculative decoding

The speed-first profile uses the fused Qwen3.8 MTP path only:

```text
--spec-type draft-mtp
--spec-draft-n-max 2
--spec-draft-n-min 0
--spec-draft-p-min 0.0
```

The model publisher's IQ2_M benchmark reports code-generation throughput peaking at the tested `n_max=2` setting (1.32x its no-spec baseline), so BLACK Code uses MTP2 instead of carrying the old MTP4 setting forward by assumption.

`ngram-mod` and forced `--cache-reuse` are disabled by default because the previously combined agentic profile regressed observed end-to-end runtime. llama.cpp remains free to use its normal internal prompt behavior; BLACK Code simply does not force the regressing cache-reuse option.

## Setup refresh without unnecessary downloads

Running normal `setup.ps1` downloads IQ2_M when it is not already present and SHA-256-valid. The older IQ4_XS file, if still present, is not selected by the launcher and can be removed manually after IQ2_M is verified if disk space is desired.

`setup.ps1 -ForceLlama` refreshes only the llama.cpp CUDA runtime. It does **not** force a model re-download. `-Force` remains the full refresh path.

## Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\BLACK-Code\launcher\doctor.ps1"
```

## Runtime boundaries

The local model server binds only to `127.0.0.1`. Qwen long-form thinking remains disabled by default through `enable_thinking=false`; this is independent from speculative decoding, which remains enabled.
