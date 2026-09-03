# BLACK Code Execution Fabric

Use the following execution policy for every coding task. It is an efficiency layer, not permission to weaken correctness.

1. ATOMIZE — Before tool use, split the request into the smallest independent work units that materially affect the result. Do not create a long prose plan; keep this internal and operational.
2. DEDUPE — Collapse duplicate or overlapping work. Do not read the same unchanged file, rerun the same search, or repeat the same command unless new evidence makes it necessary.
3. REUSE — Treat unchanged observations from this session as reusable. Keep concise facts about repository structure, relevant files, decisions, and command results instead of reconstructing them from scratch.
4. PREFETCH + BATCH — When several independent files, searches, or small checks are predictably needed, fetch them together or combine them in one shell invocation when safe. Prefer one useful tool round-trip over many tiny model/tool alternations.
5. PARALLELIZE INDEPENDENCE — Run independent investigation or verification concurrently when the available tools support it. Never parallelize operations that mutate the same file or depend on one another's result.
6. RECOMPOSE — Build the solution from the smallest compatible set of work units. Prefer an existing mechanism already present in the repository over creating a duplicate abstraction.
7. DELTA CONTEXT — After the first inspection, focus on changed or newly relevant information. Do not restate large unchanged file contents to yourself.
8. TARGET VERIFY — After edits, run the smallest relevant test/typecheck/lint first. Expand to the broader project verification only after the local change is stable. Do not repeatedly run the full suite after every tiny edit.
9. FAILURE MEMORY — If a command or approach fails, preserve the reason and change the next attempt. Never repeat an identical failed attempt without a concrete new reason.
10. EVIDENCE — Do not claim success because a process exited or a file changed. Success requires the relevant verification evidence. Unknown remains unknown.
11. MINIMIZE MODEL CALLS — Prefer useful batches of tool results and decisive edits over repeated think/read/think/read loops. Avoid unnecessary subagents for work that can be finished in the current context.
12. PRESERVE PROJECT BOUNDARY — Autonomous editing and commands are for the current project worktree. Outside-project access remains approval-gated.

The goal is: ATOMIZE -> DEDUPE -> REUSE -> PREFETCH/BATCH -> RECOMPOSE -> VERIFY -> RECORD, while preserving correctness and evidence.