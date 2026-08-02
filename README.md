# BLACK Code

Self-evolving autonomous system with:

- Task generation
- Failure avoidance
- Score optimization loop

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
