# BLACK Code 7.27 — Durable Download Handoff

The preferred long-running install entrypoint is now:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\setup-resilient.ps1 `
  -ModelWorkDir "$env:LOCALAPPDATA\BLACK-Code\model-build-7.27" `
  -HfDownloadWorkers 8
```

This wrapper does **not** replace the canonical builder. It adds an observable, resumable transfer layer before `setup.ps1` so a CLI/session handoff does not require guessing whether the Hugging Face parent download is alive.

## Durable state

During parent transfer, the following files live in the model work directory:

- `parent-download.state.json` — current phase/status, Windows HF PID, parent bytes, latest mtime, free/effective bytes, logs, pinned repo/revision.
- `parent-download.out.log` — persistent Hugging Face stdout.
- `parent-download.err.log` — persistent Hugging Face stderr.

Read-only status:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\setup-resilient.ps1 `
  -ModelWorkDir "$env:LOCALAPPDATA\BLACK-Code\model-build-7.27" `
  -TransferStatusOnly
```

## Handoff behavior

`download-parent-7.27.ps1` follows this state machine:

```text
NO STATE / STALE STATE
        |
        v
validate existing snapshot
        |
        +-- complete --> COMPLETE
        |
        v
125 GB effective-capacity gate
        |
        v
Windows venv + hf.exe
        |
        v
DOWNLOADING + durable PID/bytes/mtime/log state
        |
        +-- CLI changes while hf.exe remains alive --> attach by observation; DO NOT spawn duplicate
        |
        +-- previous hf.exe died + snapshot incomplete --> resume same SourceDir
        |
        v
full shard inventory validation
        |
        v
COMPLETE
        |
        v
canonical setup.ps1
```

The transfer layer never uses `-Force`, never purges partial data, and never kills an existing HF process merely because the supervising AI CLI changed.

## Authority rules

- A lost Codex/Hermes/OpenCode internal process handle is not evidence that Windows `hf.exe` died.
- `parent-download.state.json` plus the actual Windows PID/filesystem state is the handoff authority.
- A stale state file is not treated as active unless the recorded Windows HF PID is still alive.
- If the recorded HF process dies, the snapshot is validated before another transfer is started.
- Completed parent files stay reusable and the canonical builder performs its own integrity/snapshot validation again before conversion.

## What this fixes

The old path could spend hours inside a synchronous `hf.exe` call whose stdout/stderr lived in temporary files and whose PID/progress was not persisted. When the controlling CLI changed, the next agent had to infer whether the transfer was alive, stalled, or already dead.

The resilient path makes that state explicit and survives CLI/session handoff without turning a CLI change into a build restart.

## Future prebuilt artifact path

The source-build path remains canonical and reproducible. Once the first verified BLACK 7.27 GGUF exists, it can additionally be published as a SHA-pinned prebuilt artifact. Normal installs can then prefer:

```text
pinned prebuilt GGUF -> byte/SHA/GGUF/provenance verification -> install
```

with this source-build route retained as the reproducible fallback.
