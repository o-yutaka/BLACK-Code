param(
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") { throw "inspect-parent-7.27.ps1 must run in Windows PowerShell, not WSL/Linux." }

$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
if (-not (Test-Path -LiteralPath $LockPath)) { throw "model-7.27.lock.json is missing." }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$ParentDir = Join-Path $WorkDir "uncensored-parent"
$StatePath = Join-Path $WorkDir "parent-download-state.json"

function Get-DirectoryBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0L }
    $sum = 0L
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $sum += [int64]$_.Length }
    return $sum
}

function Get-SnapshotStatus([string]$Path) {
    $config = Join-Path $Path "config.json"
    $indexPath = Join-Path $Path "model.safetensors.index.json"
    $expected = 0
    $missing = 0
    $complete = $false
    if (Test-Path -LiteralPath $indexPath) {
        try {
            $index = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
            $shards = @($index.weight_map.PSObject.Properties | ForEach-Object { [string]$_.Value } | Sort-Object -Unique)
            $expected = $shards.Count
            foreach ($shard in $shards) {
                $path = Join-Path $Path $shard
                if (-not (Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -le 0) { $missing++ }
            }
            $complete = (Test-Path -LiteralPath $config) -and $expected -gt 0 -and $missing -eq 0
        } catch { $complete = $false }
    } else {
        $single = @(Get-ChildItem -LiteralPath $Path -Filter "*.safetensors" -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
        $expected = $single.Count
        $complete = (Test-Path -LiteralPath $config) -and $single.Count -gt 0
    }
    return [pscustomobject]@{ complete=$complete; expected=$expected; missing=$missing }
}

$recorded = $null
if (Test-Path -LiteralPath $StatePath) {
    try { $recorded = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json } catch { $recorded = $null }
}
$snapshot = Get-SnapshotStatus $ParentDir
$recordedPid = $null
if ($recorded -and $null -ne $recorded.hf_pid) { $recordedPid = [int]$recorded.hf_pid }
$process = $null
if ($null -ne $recordedPid) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $recordedPid" -ErrorAction SilentlyContinue
}
$processMatches = $false
if ($process -and $process.CommandLine) {
    $processMatches = $process.CommandLine -match 'hf\.exe|huggingface' -and $process.CommandLine -match [regex]::Escape([string]$Lock.uncensored_parent.repo)
}

$verdict = "INCOMPLETE_OR_NOT_STARTED"
if ($snapshot.complete) {
    $verdict = "VERIFIED_COMPLETE"
} elseif ($processMatches) {
    $verdict = "ACTIVE"
} elseif ($recorded -and $recorded.status -eq "DOWNLOADING") {
    $verdict = "STALE_STATE"
}

$latest = $null
if (Test-Path -LiteralPath $ParentDir) {
    $lastFile = Get-ChildItem -LiteralPath $ParentDir -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($lastFile) { $latest = $lastFile.LastWriteTimeUtc.ToString("o") }
}

[ordered]@{
    schema_version = "1.0"
    inspected_at = (Get-Date).ToString("o")
    verdict = $verdict
    windows_host = $true
    repo = [string]$Lock.uncensored_parent.repo
    revision = [string]$Lock.uncensored_parent.revision
    work_dir = $WorkDir
    parent_dir = $ParentDir
    parent_bytes = Get-DirectoryBytes $ParentDir
    latest_write_utc = $latest
    snapshot_complete = [bool]$snapshot.complete
    expected_shards = [int]$snapshot.expected
    missing_or_empty_shards = [int]$snapshot.missing
    durable_state_path = $StatePath
    durable_state_status = if ($recorded) { [string]$recorded.status } else { $null }
    durable_state_updated_at = if ($recorded) { [string]$recorded.updated_at } else { $null }
    recorded_hf_pid = $recordedPid
    recorded_hf_pid_alive_and_matching = [bool]$processMatches
    actual_process_name = if ($processMatches) { [string]$process.Name } else { $null }
    actual_process_command_line = if ($processMatches) { [string]$process.CommandLine } else { $null }
} | ConvertTo-Json -Depth 5
