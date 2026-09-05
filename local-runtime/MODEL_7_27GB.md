# BLACK Code Fixed 7.27 GB Model

BLACK Code is fixed to `Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf` as its only canonical main model.

## Identity

The parent weights are the pinned `JonathanColetti/Qwen3.8-27B-Uncensored` revision recorded in `model-7.27.lock.json`. The model is converted without MTP tensors and without any vision sidecar.

The precision allocation is copied tensor-for-tensor from the pinned Unsloth `Qwen3.8-27B-UD-IQ2_XXS.gguf` reference. BLACK Code reads only the remote GGUF tensor directory with byte ranges, checks that the local no-MTP F16 tensor-name inventory exactly matches the reference, then supplies the exact reference dtypes through llama.cpp `--tensor-type-file` with the pinned uncensored imatrix.

## Canonical governed pipeline

The supported local-build entrypoint is `run-model-pipeline-7.27.ps1`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\local-runtime\run-model-pipeline-7.27.ps1 `
  -ModelWorkDir "$env:LOCALAPPDATA\BLACK-Code\model-build-7.27" `
  -HfDownloadWorkers 8
```

The pipeline owns the entire transition:

```text
resumable parent snapshot + stall watchdog
→ indexed shard completeness proof
→ offline downstream parent revalidation
→ pinned no-MTP F16 conversion + SHA/provenance
→ pinned uncensored imatrix + SHA
→ Range-only reference tensor map + exact tensor inventory match
→ llama-quantize dry-run
→ IQ2_XXS quantization to temporary .building artifact
→ GGUF + 7.20–7.35 GB size gate
→ actual SHA-256
→ canonical manifest
→ independent final verification
→ COMPLETE
```

`model-pipeline-state.json` is written atomically in the work directory. A replacement CLI can inspect the current durable phase without restarting or purging the build:

```powershell
.\local-runtime\run-model-pipeline-7.27.ps1 -StatusOnly
```

When the parent download is already active, the parent preparation layer attaches to the matching Windows HF process instead of starting a duplicate. If transfer progress remains absent past the configured watchdog window, only the revalidated matching transfer tree is stopped; partial data is preserved and resumed. Once the parent snapshot is `VERIFIED_COMPLETE`, downstream setup runs Hugging Face validation in offline mode so a second Hub/Xet transfer cannot be started accidentally.

## Size and local immutable identity

The final GGUF must be between 7,200,000,000 and 7,350,000,000 bytes. A build outside that range is rejected and never becomes canonical.

The exact output SHA-256 cannot be truthfully hard-coded before the real quantization is executed on a concrete parent snapshot and quantizer. The first successful local build therefore writes `model-7.27.local.json` containing the exact output byte length, SHA-256, parent revision, reference revision, imatrix hash, tensor-map count and quantizer version.

The governed pipeline then independently recalculates the final GGUF SHA-256 and size and revalidates the manifest/provenance contract. `COMPLETE` is not written unless that independent verifier passes.

## Speculative decoding

The main model is no-MTP. Runtime speculative decoding uses the separately pinned uncensored Q4_0 MTP draft from `model-7.27.lock.json` with `draft-mtp` and max draft width 2.

## No fallback

IQ2_M and IQ4_XS are superseded. Setup rebuilds the fixed 7.27 model if it is absent or invalid rather than silently changing to another quantization class.

## Storage behavior

The initial source build requires the canonical effective-capacity gate defined by the builder. Parent partials are reusable capacity and are not deleted merely because a transfer stalls or the controlling CLI changes. Parent material is released only after the F16 artifact and its provenance have been verified. Large intermediate F16/tensor artifacts are removed after a successful build unless maintenance mode explicitly retains them.

Docker is not required. WSL may be used as a controller to invoke the Windows runtime; the actual model build/runtime executables remain Windows-native.
