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

llama.cpp, logs and generated OpenCode runtime configuration are kept under the same `%LOCALAPPDATA%\BLACK-Code` tree.

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

## Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\BLACK-Code\launcher\doctor.ps1"
```

## Runtime boundaries

The local model server binds only to `127.0.0.1`. The selected GGUF contains MTP data, but speculative MTP decoding is not enabled by default; the first target is a stable coding-agent path on the actual 10 GB VRAM / 32 GB RAM machine.
