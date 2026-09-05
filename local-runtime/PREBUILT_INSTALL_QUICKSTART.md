# BLACK Code 7.27 quick path

## First proven build only

Preferred one-command entrypoint:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\setup-resumable-7.27.ps1
```

That wrapper:

1. verifies whether the canonical 7.27 GB model already exists;
2. if not, runs `prepare-parent-7.27.ps1` first so the pinned parent download is resumable and continuously recorded in `parent-download-state.json`;
3. then enters the existing canonical `setup.ps1` path to complete F16 -> exact tensor map -> IQ2_XXS -> actual SHA256 -> canonical local manifest;
4. never uses force/purge unless explicitly requested.

If only the parent should be downloaded and verified now, without starting conversion/quantization:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\prepare-parent-7.27.ps1
```

Inspect durable state without starting another download:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\prepare-parent-7.27.ps1 `
  -StatusOnly
```

After the first real source build is fully verified, publish the exact GGUF + manifest once with `publish-prebuilt-7.27.ps1`.

## Every later clean install

1. Run `install-prebuilt-7.27.ps1` with the published model URL, manifest URL, and actual SHA256.
2. Run `setup-resumable-7.27.ps1` normally.
3. The wrapper verifies the existing canonical model, skips parent preload, and `setup.ps1` skips the expensive parent/F16/quantization path.

This is the intended end state: build once, verify once, distribute the exact proven 7.27 GB artifact, and stop repeatedly transferring the much larger parent snapshot.
