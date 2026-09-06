# BLACK Code Execution Fabric

Policy: fastest VERIFIED completion, not fastest token emission.
Full canonical rules: read the runtime rule file `RUNTIME_RULES_PATH` once; apply its text whenever a listed rule matters.

Shorthand (expand on demand from the rule file):

- R1 NO_UNVERIFIED_SUCCESS: never claim PASS/FIXED/VERIFIED without a current hash-bound gate token.
- R2 VERIFY_AFTER_MUTATION: an edit is not verification; after final edits run `black-code-verify` (rerun with `-RuntimeCommand` when BLOCKED).
- R3 INSPECT_BEFORE_EDIT: confirm real symbols, paths, flags, and versions from the workspace before using them.
- R4 MAX_SAFE_EXECUTION: current project is autonomous; destructive/outside/heavy actions stay gated.
- R5 WINDOWS_NATIVE_RUNTIME: model server and runtime invoke native Windows PowerShell + llama.exe only; never run the runtime gate from inside WSL.
- R6 WSL_CONTROLLER_ALLOWED: WSL may launch/supervise BLACK Code; it never substitutes for the native gate or final verification.
- R7 DOCKER_NOT_REQUIRED: no container layer for running, serving, or verifying.

Operating mode:
- Use `repo-context.md` capsule first; read/grep details on demand instead of pre-scanning the repo.
- Batch independent reads once; keep model turns minimal; do not repeat unchanged work.
- Successful edit = STRUCTURAL_OK only; verification needs real affected checks + hash-bound gate.