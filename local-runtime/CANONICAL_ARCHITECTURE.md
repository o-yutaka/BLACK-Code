# BLACK Code Canonical Architecture v4

## Boundary

BLACK Code is the local coding runtime/source-testbed. BLACK is a separate system. Code Knowledge belongs on the BLACK side; BLACK Code may later export verified experience packets, but normal coding execution never imports or mutates BLACK.

The older Python Claude-style BLACK Code remains donor/reference only, not a second production runtime.

## Canonical ownership

| Capability | Canonical owner | Decision |
| --- | --- | --- |
| terminal coding UI and tool execution | OpenCode | KEEP |
| local model serving | llama.cpp CUDA | KEEP |
| main model | BLACK 7.27 uncensored custom GGUF | FIXED |
| local model inference concurrency | one slot | KEEP |
| speculative decoding | external uncensored Q4_0 MTP, max2 | KEEP |
| repository structure/delta | `repo-index.ps1` | KEEP |
| affected test hints | `repo-index.ps1` + agent policy | KEEP/strengthen |
| context/VRAM policy | `black-code.ps1` | KEEP |
| tool/model bottleneck telemetry | OpenCode telemetry + llama logs | KEEP |
| Claude/BLACK rule hierarchy | `rule-bridge.ps1` | KEEP |
| duplicate skill loader | none | DROP; use OpenCode native discovery |
| donor custom Python TUI/router/server | donor/reference only | DROP from canonical runtime |
| syntax-only post-edit success | `STRUCTURAL_OK` only | NEVER final verification |
| final verification | `verification-gate.ps1` / `black-code-verify` | CANONICAL |
| final claim authority | `opencode-governor.js` | CANONICAL |
| vision | none | DROP |
| Hugging Face parent transfer | HF/Xet high performance | CANONICAL |
| fixed artifact transfer | parallel range downloader + hash | CANONICAL |

## Fixed model

Canonical main model:

```text
Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf
```

Its build identity is locked by `model-7.27.lock.json`:

1. pinned `JonathanColetti/Qwen3.8-27B-Uncensored` parent revision;
2. pinned no-MTP conversion path;
3. pinned Unsloth 7.27 GGUF tensor-precision reference revision;
4. exact tensor-name inventory equality before quantization;
5. pinned uncensored importance matrix;
6. current llama quantizer must support `--tensor-type-file`;
7. dry-run before real quantization;
8. final GGUF must be between 7.20 and 7.35 GB decimal;
9. final SHA-256 is written to `model-7.27.local.json` and becomes the local immutable artifact identity.

The 10.6 GB IQ2_M runtime is superseded and is not an automatic fallback.

The main GGUF excludes MTP tensors. Speculative decoding uses the separately pinned `Qwen3.8-27B-Uncensored-draft-Q4_0.gguf` with max draft width 2. Vision is absent.

## Model build path

```text
PINNED UNCENSORED PARENT
        |
        v
PARALLEL HF/XET SNAPSHOT
        |
        v
PINNED LLAMA CONVERTER --no-mtp
        |
        v
F16 GGUF
        |
        +---------------------------+
        |                           |
        v                           v
PINNED 7.27 REFERENCE          PINNED IMATRIX
Range-only tensor directory         |
        |                           |
        +------------+--------------+
                     v
             TENSOR INVENTORY EQUAL
                     |
                     v
           EXACT TENSOR TYPE FILE
                     |
                     v
             QUANTIZER DRY RUN
                     |
                     v
                QUANTIZE
                     |
                     v
           7.20..7.35 GB GATE
                     |
                     v
                  SHA256
                     |
                     v
          LOCAL CANONICAL MANIFEST
```

A Range server returning the full reference instead of HTTP 206 is rejected. BLACK Code never downloads the 7.27 reference in full merely to copy its tensor allocation.

## Runtime state machine

```text
CLEAN/KNOWN
   |
   v
INDEX + RULES
   |
   v
INSPECT/BATCH
   |
   v
EDIT -----------------------------+
   |                               |
   v                               |
DIRTY                              |
   |                               |
   v                               |
STRUCTURAL_OK                      |
   |                               |
   v                               |
RESOLVE                            |
   |                               |
   v                               |
AFFECTED_VERIFY                    |
   |                               |
   v                               |
FINAL_VERIFY --fail--> REPAIR -----+
   |
   v
WORKSPACE_HASH + VERIFY_PROFILE
   |
   v
VERIFICATION_TOKEN
   |
   v
FINAL/RECORD
```

Any mutation after final verification invalidates the token.

## Definition of usable code

For an implementation request, parseability is not usability. The strongest relevant checks available must establish the material parts of:

```text
syntax/structure
AND real dependency/symbol resolution
AND build/type validity where applicable
AND affected tests/checks
AND requested entrypoint/runtime behavior when project checks are insufficient
```

If no strong standard verification path exists, `black-code-verify` returns BLOCKED until a real task-specific `-RuntimeCommand` is supplied. No-op commands cannot satisfy the gate.

## Completion authority

The model can propose completion but cannot authorize it. `opencode-governor.js` owns final-claim admission by binding successful final verification to the current workspace fingerprint, invalidating that proof after mutations, preserving unverified continuity across restarts and rejecting identical failed shell retries against the same workspace state.

## Performance objective

Primary metric:

```text
verified task latency
```

Supporting metrics include first-pass verified rate, invalid import/API rate, tool-call validity, retry count, TTFT, decode tokens/sec, MTP effect, prompt/prefill time, tool time, verification time and VRAM/spill behavior. A faster decoder that produces more repair loops is a regression.
