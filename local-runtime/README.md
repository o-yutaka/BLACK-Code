# BLACK Code Local Runtime

This directory is the canonical Windows local coding runtime for BLACK Code.

## Canonical architecture

```text
OpenCode 1.18.28 (pinned)
  -> BLACK execution instructions + repo delta context + Claude/BLACK rule bridge
  -> Qwen3.8-27B Uncensored BLACK 7.27 through pinned llama.cpp b10809 CUDA 12.4
  -> external Uncensored Q4_0 MTP draft, max 2
  -> project-local tools
  -> untracked-aware affected verification
  -> black-code-verify final gate
  -> workspace + runtime bound completion governor
  -> telemetry / bottleneck / session evidence
```

The older Python Claude-style runtime is donor/reference only. BLACK itself remains separate; verified BLACK Code experience may later feed BLACK's Code Knowledge capability.

## Fixed model policy

BLACK Code has one canonical main model:

- file: `Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf`
- parent: `JonathanColetti/Qwen3.8-27B-Uncensored` at pinned revision `5bb7aa90f0efef548e87005b1fb7658e522b6b7f`
- main model: no-MTP, text/code only
- target byte window: 7.20..7.35 GB decimal
- quantization: exact tensor precision map from the pinned Unsloth `Qwen3.8-27B-UD-IQ2_XXS.gguf` reference, applied to the pinned uncensored parent with the pinned uncensored imatrix
- output SHA-256: generated on the first successful local build and then pinned in `model-7.27.local.json`
- MTP: separate `Qwen3.8-27B-Uncensored-draft-Q4_0.gguf`, fixed SHA-256, max draft width 2
- vision: absent

The former 10.6 GB IQ2_M model is superseded. Setup does not silently fall back to it.

## Pinned runtime policy

BLACK Code does not install "whatever is latest today". `runtime.lock.json` fixes the executable environment used by the coding runtime:

```text
OpenCode          1.18.28
llama.cpp         b10809 (v0.4.0 line)
llama commit      5266f24da75dc449bd56cbed7addb9c8e4a6a73e
CUDA              12.4 / Windows x64
main ZIP SHA256   c77bfcd9ed8d91e8721a2d6a290b907fddd4fa5412a47b21c6fa1709116b85f9
cudart SHA256     8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6
```

Setup enforces those versions and verifies both llama.cpp ZIP hashes before extraction. Doctor rejects version drift.

## How the first build works

`setup.ps1` makes the fixed model automatically if it does not already exist:

```text
pinned uncensored HF parent
  -> parallel HF/Xet snapshot transfer
  -> pinned llama.cpp converter
  -> no-MTP F16 GGUF
  -> remote Range-only parse of pinned 7.27 reference tensor directory
  -> exact tensor-name inventory match
  -> pinned uncensored imatrix
  -> llama-quantize --tensor-type-file dry-run
  -> real quantization
  -> 7.20..7.35 GB size gate
  -> GGUF magic check
  -> SHA-256
  -> model-7.27.local.json
```

The reference 7.27 GB GGUF is not downloaded in full just to obtain its tensor map. Only its GGUF header/tensor directory is fetched with HTTP byte ranges. A server that ignores Range requests is rejected.

The build needs roughly 125 GB of free temporary working space because the pinned parent and intermediate F16 GGUF coexist during conversion. Unless `-KeepIntermediate` is explicitly used by the builder, the large parent snapshot is removed after F16 conversion and the F16/intermediate files are removed after the final model is pinned.

## Hugging Face transfer

Large parent snapshot transfer uses `hf_xet` high-performance mode. Fixed standalone artifacts such as the MTP draft use `hf-parallel-download.ps1`, which defaults to 8 byte-range workers, validates chunk lengths and joined length, and falls back to resumable single-stream transfer if range mode fails. Artifact hashes are still checked after transfer.

## One-command use

First installation/update from the repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-runtime\setup.ps1
```

After bootstrap:

```bat
black-code
```

Final verification:

```bat
black-code-verify
```

For a project without a sufficiently strong standard verify/test/build path:

```bat
black-code-verify -RuntimeCommand "<real entrypoint or smoke command>"
```

No-op runtime commands are rejected.

## RTX 3060 12 GB canonical runtime

```text
main model            BLACK UD-IQ2_XXS 7.27 GB-class, locally SHA-pinned
MTP draft             Uncensored Q4_0 external draft
MTP draft max         2
context               auto 8K / 12K / 16K
output cap            auto 4K / 6K / 8K
fit target headroom   1,024 MiB
parallel model slots  1
KV K/V                 q8_0 / q8_0
thinking               off
vision                 off
ngram-mod              off
forced cache-reuse     off
```

Independent CPU-side reads, indexing, hashing and checks may be parallelized. Local 27B inference remains one active slot.

## Execution and verification

```text
INDEX -> RULES -> DELTA -> BATCH -> EDIT
      -> STRUCTURAL_OK -> RESOLVE
      -> AFFECTED_VERIFY -> FINAL_VERIFY
      -> WORKSPACE_HASH + RUNTIME_HASH
      -> HASH_BIND -> RECORD
```

`STRUCTURAL_OK` is never completion evidence. `black-code-verify` selects the strongest standard project checks it can find; when that is insufficient it returns `BLOCKED` until a real task-specific runtime command is supplied.

`opencode-governor.js` binds successful final verification to both the current workspace and relevant runtime environment. The runtime fingerprint covers the installed runtime state, local model manifest, verifier, governor, project rules/instructions and observable runtime versions. Later project edits or relevant runtime/model/rule/verifier changes invalidate the token, including across sessions. Identical failed shell commands against the exact same workspace + runtime state are rejected.

## Repository context

`repo-index.ps1` v2 persists HEAD, tracked delta, **untracked/new files**, package roots, test files and likely affected tests. A newly created source or test file is first-class delta and cannot be hidden by `git status -uno` behavior.

`rule-bridge.ps1` imports compatible `CLAUDE.md`, `CLAUDE.local.md`, `BLACK.md` and non-fenced `@file` references. OpenCode's native skill discovery remains authoritative; BLACK Code does not duplicate it.

## Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\BLACK-Code\launcher\doctor.ps1"
```

Doctor exits non-zero if the fixed model, local model SHA manifest, MTP draft, pinned OpenCode/llama.cpp runtime, governed components or canonical state are invalid.

The model server binds only to `127.0.0.1`; outside-project access remains approval-gated.
