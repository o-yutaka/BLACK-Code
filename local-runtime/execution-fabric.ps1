Set-StrictMode -Version Latest

function Get-BlackCodeSha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-BlackCodeProjectIdentity([string]$ProjectRoot) {
    $resolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $gitHead = $null
    $gitDirty = $null
    $git = Get-Command "git.exe" -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command "git" -ErrorAction SilentlyContinue }

    if ($git) {
        $head = (& $git.Source -C $resolved rev-parse HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $head) {
            $gitHead = ([string]$head).Trim()
            $status = @(& $git.Source -C $resolved status --porcelain=v1 -uno 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $gitDirty = $status.Count -gt 0
            }
        }
    }

    $basis = if ($gitHead) { "$resolved|$gitHead" } else { $resolved }
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
        schema_version = "1.1"
        profile_name = "black-execution-fabric-measured-fast-v1"
        design_source = "BLACK atomize/overlap/recompose/utility/learning-policy pattern; copied as design only"
        authority = [ordered]@{
            may_edit_project = $true
            may_edit_outside_project = $false
            may_self_claim_success = $false
        }
        atoms = @(
            "task.atomize",
            "work.dedupe-overlap",
            "context.reuse-session",
            "tool.prefetch-batch",
            "decode.mtp4",
            "verify.targeted-then-broad",
            "experience.session-evidence"
        )
        rejected_atoms = @(
            [ordered]@{
                atom = "decode.ngram-mod"
                reason = "measured_agentic_regression"
                default_enabled = $false
            },
            [ordered]@{
                atom = "prompt.cache-reuse-256"
                reason = "measured_agentic_regression_or_unproven_benefit"
                default_enabled = $false
            }
        )
        inference = [ordered]@{
            speculative_types = @("draft-mtp")
            mtp_draft_max = 4
            mtp_draft_min = 0
            mtp_probability_min = 0.0
            forced_cache_reuse = $false
            context = $Context
            fit_target_mib = $FitTargetMiB
        }
        execution = [ordered]@{
            atomize_before_tools = $true
            dedupe_equivalent_work = $true
            reuse_unchanged_observations = $true
            batch_independent_reads_and_searches = $true
            parallelize_only_independent_work = $true
            verify_smallest_relevant_scope_first = $true
            broad_verify_after_patch_stabilizes = $true
            reject_regressing_atoms = $true
        }
    }

    $canonical = $body | ConvertTo-Json -Depth 12 -Compress
    return [ordered]@{
        profile = $body
        canonical_hash = Get-BlackCodeSha256 $canonical
    }
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
        schema_version = "1.0"
        recorded_at = (Get-Date).ToString("o")
        started_at = $StartedAt.ToString("o")
        completed_at = $CompletedAt.ToString("o")
        duration_ms = $durationMs
        process_exit_code = $ExitCode
        verification_status = "UNVERIFIED"
        profile_name = $ProfileEnvelope.profile.profile_name
        profile_hash = $ProfileEnvelope.canonical_hash
        project = $ProjectIdentity
        hardware = [ordered]@{
            gpu = $GpuName
            free_vram_mib_at_start = $FreeVramMiB
            total_vram_mib = $TotalVramMiB
        }
        logs = [ordered]@{
            stdout = $StdoutLog
            stderr = $StderrLog
        }
    }
    $recordHashInput = $record | ConvertTo-Json -Depth 12 -Compress
    $record["canonical_hash"] = Get-BlackCodeSha256 $recordHashInput
    $record | ConvertTo-Json -Depth 12 -Compress | Add-Content -Encoding UTF8 (Join-Path $EvidenceDir "sessions.jsonl")
}
