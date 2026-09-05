# BLACK Code 7.27 distribution path

BLACK Code keeps two separate paths for the canonical model.

## A. Source-build path

Use this only when the canonical prebuilt GGUF does not exist yet, or when an intentional reproducibility rebuild is required.

1. `prepare-parent-7.27.ps1` downloads only the pinned uncensored parent and stops after shard-completeness verification.
2. The parent stays in the normal `model-build-7.27\uncensored-parent` location, so an interrupted CLI/session does not require a fresh download.
3. `parent-download-state.json` is updated while Windows `hf.exe` is active. A replacement CLI can inspect that state instead of guessing from an old CLI process id.
4. If the same WorkDir already has an active matching Windows `hf.exe`, rerunning `prepare-parent-7.27.ps1` attaches by observation and waits; it does not spawn a duplicate transfer.
5. If that attached transfer ends before snapshot completeness, the same partial `SourceDir` is preserved and resumed without force/purge.
6. Normal `setup.ps1` reuses the verified parent through the existing resume/integrity path and continues F16 -> imatrix -> tensor map -> dry run -> IQ2_XXS -> local manifest.

Preferred one-command source-build/resume entrypoint:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\setup-resumable-7.27.ps1 `
  -ModelWorkDir "$env:LOCALAPPDATA\BLACK-Code\model-build-7.27" `
  -HfDownloadWorkers 8
```

This is the handoff-safe entrypoint to give a replacement Codex/Hermes/OpenCode session. It first reuses/attaches/resumes the parent transfer, then enters canonical `setup.ps1` only after the parent snapshot is verified complete.

Prepare only the parent:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\prepare-parent-7.27.ps1
```

Inspect the last durable state without starting a second download:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\prepare-parent-7.27.ps1 `
  -StatusOnly
```

For a process-grounded read-only verdict, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\inspect-parent-7.27.ps1
```

Do not run `-Force`, `-ForceRebuild`, or purge options merely because the controlling AI CLI changed.

## B. Prebuilt-install path (preferred after the first proven build)

After one real-machine build has produced the canonical 7.20-7.35 GB GGUF and its exact `model-7.27.local.json`, publish those two verified artifacts once.

The publisher refuses to upload a model whose local bytes/SHA/provenance manifest do not match.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\publish-prebuilt-7.27.ps1 `
  -RepoId "OWNER/BLACK-Code-7.27"
```

The command prints:

- exact model URL
- exact manifest URL
- actual SHA256

Future clean installs can then skip the large parent/F16/quantization pipeline:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\install-prebuilt-7.27.ps1 `
  -ModelUrl "<published model URL>" `
  -ManifestUrl "<published manifest URL>" `
  -ExpectedSha256 "<actual SHA256>"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\setup.ps1
```

`install-prebuilt-7.27.ps1` uses resumable range transport and verifies:

- GGUF magic
- 7,200,000,000..7,350,000,000 byte canonical size window
- exact SHA256
- canonical manifest status/schema
- pinned parent revision
- reference/imatrix provenance
- tensor inventory/F16 provenance
- canonical quantization contract

The stable `.prebuilt-7.27-stage` directory is intentionally preserved after a failed transfer. Existing `.part` and completed `.chunks` data survive the failed install and are reused on the next invocation. The stage is removed only after model + manifest verification and successful promotion into the runtime model directory.

Because `setup.ps1` already calls `Test-CanonicalModel`, a correctly installed prebuilt model is reused and the expensive source build is skipped.

## Distribution policy

The Git repository itself must not contain the multi-gigabyte GGUF. GitHub regular Git/LFS has per-file limits that are too small for the 7.27 GB artifact. Keep code, lock files, SHA/provenance and installers in GitHub; keep the actual GGUF in a large-file artifact host such as Hugging Face. A GitHub Release can also be used only if the model is split into sub-2-GiB assets and reassembled with verified hashes.

## Canonical truth

Prebuilt distribution does not weaken provenance. The first source build is still required to create the canonical artifact. Once that artifact is proven, future installs verify and reuse that exact artifact instead of repeating the expensive build graph.
