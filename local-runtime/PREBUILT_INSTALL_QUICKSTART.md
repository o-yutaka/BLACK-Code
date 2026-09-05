# BLACK Code 7.27 quick path

## First proven build only

1. Run `prepare-parent-7.27.ps1` once to finish and verify the pinned parent download while continuously writing `parent-download-state.json`.
2. Run normal `setup.ps1` to reuse that parent and complete F16 -> exact tensor map -> IQ2_XXS -> actual SHA256 -> canonical local manifest.
3. Publish the verified GGUF + manifest once with `publish-prebuilt-7.27.ps1`.

## Every later clean install

1. Run `install-prebuilt-7.27.ps1` with the published model URL, manifest URL, and actual SHA256.
2. Run normal `setup.ps1`.
3. `setup.ps1` verifies the existing canonical model and skips the expensive parent/F16/quantization path.

This is the intended end state: build once, verify once, distribute the exact proven 7.27 GB artifact, and stop repeatedly transferring the much larger parent snapshot.
