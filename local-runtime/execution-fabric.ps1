Set-StrictMode -Version Latest

function Get-BlackCodeSha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BlackCodeProjectIdentity([string]$ProjectRoot) {
    $resolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $gitHead = $null
    $gitDirty = $null
    $git = Get-Command "git.exe" -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command "git" -ErrorAction SilentlyContinue }

    if ($git) {
        $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        try {
            $head = (& $git.Source -C $resolved rev-parse HEAD 2>$null | Select-Object -First 1)
            if ($LASTEXITCODE -eq 0 -and $head) {
                $gitHead = ([string]$head).Trim()
                # Untracked files are part of BLACK Code project state and must mark the project dirty.
                $status = @(& $git.Source -C $resolved status --porcelain=v1 --untracked-files=all 2>$null)
                if ($LASTEXITCODE -eq 0) { $gitDirty = $status.Count -gt 0 }
            }
        }
        finally { $ErrorActionPreference = $eap }
    }

    $basis = if ($gitHead) { "$resolved|$gitHead|dirty=$gitDirty" } else { $resolved }
    return [ordered]@{
        root = $resolved
        git_head = $gitHead
        git_dirty = $gitDirty
        fingerprint = Get-BlackCodeSha256 $basis
    }
}

function New-BlackCodeExecutionProfile(
    [int]$Context,
    [int]$FitTargetMiB
) {
    $body = [ordered]@{
        schema_version = "1.5"
        profile_name = "black-execution-fabric-governed-v4-7.27"
        previous_profile_name = "black-execution-fabric-governed-v3-7.27"
        design_source = "BLACK atomize/overlap/recompose/utility/learning-policy pattern; copied as design only"
        authority = [ordered]@{
            may_edit_project = $true
            may_edit_outside_project = $false
            may_self_claim_success = $false
            final_success_requires_current_verification_token = $true
        }
        atoms = @(
            "task.atomize",
            "work.dedupe-overlap",
            "context.reuse-session",
            "context.repo-delta-index-untracked-v2",
            "rules.claude-black-bridge",
            "tool.prefetch-batch",
            "runtime.pinned-opencode-llama",
            "decode.black-7.27-external-mtp2",
            "verify.structural-not-success",
            "verify.targeted-then-final",
            "verify.workspace-runtime-bound-final-v3",
            "continuity.unverified-state",
            "experience.session-evidence"
        )
        rejected_atoms = @(
            [ordered]@{ atom = "decode.ngram-mod"; reason = "measured_agentic_regression"; default_enabled = $false },
            [ordered]@{ atom = "prompt.cache-reuse-256"; reason = "measured_agentic_regression_or_unproven_benefit"; default_enabled = $false },
            [ordered]@{ atom = "runtime.parallel-model-inference"; reason = "12gb_vram_single_27b_runtime"; default_enabled = $false },
            [ordered]@{ atom = "runtime.vision-sidecar"; reason = "text-code-only-canonical"; default_enabled = $false },
            [ordered]@{ atom = "decode.iq2m-fallback"; reason = "7.27gb_model_is_now_fixed_canonical"; default_enabled = $false },
            [ordered]@{ atom = "runtime.latest-unpinned"; reason = "reproducibility_requires_runtime_lock"; default_enabled = $false }
        )
        inference = [ordered]@{
            canonical_model = "Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf"
            canonical_status = "fixed-local-build-hash-pinned"
            quantization = "BLACK-UD-IQ2_XXS-exact-reference-map"
            no_mtp_main = $true
            external_mtp_draft = "Qwen3.8-27B-Uncensored-draft-Q4_0.gguf"
            speculative_types = @("draft-mtp")
            mtp_draft_max = 2
            mtp_draft_min = 0
            mtp_probability_min = 0.0
            forced_cache_reuse = $false
            local_parallel_slots = 1
            vision = $false
            context = $Context
            fit_target_mib = $FitTargetMiB
        }
        runtime = [ordered]@{
            lock_file = "runtime.lock.json"
            opencode = "1.18.28"
            llama_binary_tag = "b10809"
            llama_commit = "5266f24da75dc449bd56cbed7addb9c8e4a6a73e"
            cuda = "12.4"
        }
        execution = [ordered]@{
            atomize_before_tools = $true
            dedupe_equivalent_work = $true
            reuse_unchanged_observations = $true
            batch_independent_reads_and_searches = $true
            parallelize_only_independent_cpu_work = $true
            include_untracked_files_in_delta = $true
            verify_smallest_relevant_scope_first = $true
            run_final_verification_after_patch_stabilizes = $true
            bind_verification_to_workspace_and_runtime_hash = $true
            runtime_change_invalidates_verification = $true
            reject_identical_failed_retry_same_workspace_and_runtime = $true
            preserve_unverified_state_across_sessions = $true
            reject_regressing_atoms = $true
        }
    }

    $canonical = $body | ConvertTo-Json -Depth 12 -Compress
    return [ordered]@{ profile = $body; canonical_hash = Get-BlackCodeSha256 $canonical }
}

function Write-BlackCodeSessionEvidence(
    [string]$EvidenceDir,
    [System.Collections.IDictionary]$ProfileEnvelope,
    [System.Collections.IDictionary]$ProjectIdentity,
    [datetime]$StartedAt,
    [datetime]$CompletedAt,
    [int]$ExitCode,
    [string]$GpuName,
    [int]$FreeVramMiB,
    [int]$TotalVramMiB,
    [string]$StdoutLog,
    [string]$StderrLog
) {
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $durationMs = [Math]::Round(($CompletedAt - $StartedAt).TotalMilliseconds)
    $record = [ordered]@{
        schema_version = "1.2"
        recorded_at = (Get-Date).ToString("o")
        started_at = $StartedAt.ToString("o")
        completed_at = $CompletedAt.ToString("o")
        duration_ms = $durationMs
        process_exit_code = $ExitCode
        verification_status = "TASK_LEVEL_GOVERNED_EXTERNALLY"
        profile_name = $ProfileEnvelope.profile.profile_name
        previous_profile_name = $ProfileEnvelope.profile.previous_profile_name
        profile_hash = $ProfileEnvelope.canonical_hash
        runtime = $ProfileEnvelope.profile.runtime
        project = $ProjectIdentity
        hardware = [ordered]@{
            gpu = $GpuName
            free_vram_mib_at_start = $FreeVramMiB
            total_vram_mib = $TotalVramMiB
        }
        logs = [ordered]@{ stdout = $StdoutLog; stderr = $StderrLog }
    }
    $recordHashInput = $record | ConvertTo-Json -Depth 12 -Compress
    $record["canonical_hash"] = Get-BlackCodeSha256 $recordHashInput
    $record | ConvertTo-Json -Depth 12 -Compress | Add-Content -Encoding UTF8 (Join-Path $EvidenceDir "sessions.jsonl")
}
