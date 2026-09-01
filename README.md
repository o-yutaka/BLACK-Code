# BLACK Code

Self-evolving autonomous system with:

- Task generation
- Failure avoidance
- Score optimization loop

## Local coding runtime — Qwen3.8-27B Uncensored

BLACK Code now has a Windows local coding path built around:

- **Qwen3.8-27B-Uncensored IQ4_XS** (~15.3 GB)
- llama.cpp CUDA
- automatic VRAM fitting with system-RAM spillover
- OpenCode as the coding-agent interface
- autonomous file creation/editing and project shell commands

The model and runtime binaries are stored outside Git under `%LOCALAPPDATA%\BLACK-Code\runtime`.

### First run

From the BLACK-Code repository on Windows:

```bat
BLACK-CODE.cmd
```

The first run automatically bootstraps the local runtime, downloads and SHA-256 verifies the GGUF, starts llama.cpp, verifies the local API, and launches OpenCode.

After bootstrap, the user command `black-code` is installed. Open a terminal in any repository you want BLACK Code to work on and run:

```bat
black-code
```

Inside that repository, OpenCode is configured to read, create, edit, patch and delete project files through its tools/shell, run build/test/lint/install commands, and iterate without asking for approval on every project-local operation. Access outside the opened repository remains approval-gated.

For the target 10 GB VRAM / 32 GB RAM class machine, the default context is 24,576 tokens and llama.cpp dynamically fits the model into available VRAM while keeping headroom for Windows.

See [`local-runtime/README.md`](local-runtime/README.md) for runtime details and diagnostics.

## BLACK Sentinel — Codex Pet

`codex-pet/` contains a complete Codex V2 companion package designed for BLACK Code.

- Transparent PNG atlas: **1536 × 2288**
- Grid: **8 × 11 / 88 frames**
- State-specific signals for idle, work, waiting, review, and failure
- Safe Windows and macOS/Linux installers with SHA-256 verification
- Deterministic generator and GitHub Actions validation

### Windows

```powershell
cd codex-pet
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

### macOS / Linux

```bash
cd codex-pet
chmod +x install.sh
./install.sh
```

Restart Codex and select **BLACK Sentinel** from custom pets.

See [`codex-pet/README.md`](codex-pet/README.md) for the design contract and validation steps.
