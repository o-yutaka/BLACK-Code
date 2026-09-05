# BLACK Code Native Windows Boundary

## Canonical host

BLACK Code canonical runtime is **native Windows only**.

Required host boundary:

```text
Windows 10/11
  -> native Windows PowerShell / CMD
  -> native Windows Python / Git / Node / curl
  -> native NVIDIA driver / CUDA llama.cpp
  -> OpenCode
  -> BLACK 7.27 local runtime
```

## Explicit non-dependencies

The canonical runtime does **not** depend on:

- Docker Desktop
- Docker Engine
- Docker containers
- WSL / WSL2
- Linux Python
- Linux shell process ownership
- `/mnt/c` path translation
- `\\wsl$` / `\\wsl.localhost` paths

Those systems may exist on the same PC for unrelated work, but they are outside the BLACK Code runtime trust boundary.

## Why the boundary is strict

A Windows executable launched through WSL interop still reports `Windows_NT`, so an OS-only check is insufficient. It can leave process ownership, environment variables, path semantics and long-running download supervision split across Windows and Linux. That was a recurring source of ambiguous HF/Xet process state.

`assert-native-windows.ps1` therefore rejects:

1. non-Windows hosts;
2. `WSL_INTEROP` / `WSL_DISTRO_NAME` inheritance;
3. WSL UNC working directories;
4. non-drive-letter `LOCALAPPDATA`;
5. non-native PowerShell executable paths;
6. WSL/Docker bridge processes in the controller ancestry.

## Canonical setup entrypoint

From **Windows CMD or Windows PowerShell opened directly**:

```bat
local-runtime\BLACK-Code-Native.cmd
```

That entrypoint verifies the native boundary before entering the resumable 7.27 setup path.

The source-build state remains under:

```text
%LOCALAPPDATA%\BLACK-Code\model-build-7.27
```

HF partials are preserved across retries. CLI replacement does not require Docker, WSL or a fresh model download.

## Rule

```text
DOCKER / WSL INSTALLED ON THE MACHINE
!=
DOCKER / WSL PART OF BLACK CODE
```

Canonical BLACK Code execution must not be controlled through Docker or WSL interop.
