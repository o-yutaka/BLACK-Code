# BLACK Code Fixed 7.27 GB Model

BLACK Code is fixed to `Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf` as its only canonical main model.

## Identity

The parent weights are the pinned `JonathanColetti/Qwen3.8-27B-Uncensored` revision recorded in `model-7.27.lock.json`. The model is converted without MTP tensors and without any vision sidecar.

The precision allocation is copied tensor-for-tensor from the pinned Unsloth `Qwen3.8-27B-UD-IQ2_XXS.gguf` reference. BLACK Code reads only the remote GGUF tensor directory with byte ranges, checks that the local no-MTP F16 tensor-name inventory exactly matches the reference, then supplies the exact reference dtypes through llama.cpp `--tensor-type-file` with the pinned uncensored imatrix.

## Size and local immutable identity

The final GGUF must be between 7,200,000,000 and 7,350,000,000 bytes. A build outside that range is rejected and never becomes canonical.

The exact output SHA-256 cannot be truthfully hard-coded before the real quantization is executed on a concrete parent snapshot and quantizer. The first successful local build therefore writes `model-7.27.local.json` containing the exact output byte length, SHA-256, parent revision, reference revision, imatrix hash, tensor-map count and quantizer version. From that point forward BLACK Code accepts only the model matching that local manifest.

## Speculative decoding

The main model is no-MTP. Runtime speculative decoding uses the separately pinned uncensored Q4_0 MTP draft from `model-7.27.lock.json` with `draft-mtp` and max draft width 2.

## No fallback

IQ2_M and IQ4_XS are superseded. Setup rebuilds the fixed 7.27 model if it is absent or invalid rather than silently changing to another quantization class.

## Build command

Normal users do not need a separate model command; `setup.ps1` invokes the builder automatically. For direct maintenance:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\build-model-7.27.ps1
```

The initial build requires approximately 125 GB free temporary working space. Large parent transfer uses high-performance HF/Xet. Intermediate parent/F16 material is removed after a successful build unless `-KeepIntermediate` is supplied.
