param(
    [switch]$Force,
    [switch]$ForceLlama,
    [string]$ModelWorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [switch]$PurgeModelDownloadCache,
    [ValidateRange(1,16)][int]$HfDownloadWorkers = 8,
    [ValidateRange(60,7200)][int]$ParentStallSeconds = 900,
    [ValidateRange(0,20)][int]$ParentMaxStallRestarts = 4,
    [ValidateRange(1,300)][int]$ParentRetryBackoffSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0

$NativeGuard = Join-Path $PSScriptRoot "assert-native-windows.ps1"
if (-not (Test-Path -LiteralPath $NativeGuard)) { throw "assert-native-windows.ps1 is missing." }
. $NativeGuard -Quiet

$Setup = Join-Path $PSScriptRoot "setup.ps1"
$Prepare = Join-Path $PSScriptRoot "prepare-parent-7.27.ps1"
$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
foreach ($required in @($Setup,$Prepare,$LockPath)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required resumable setup input missing: $required" } }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$ModelDir = Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\models"
$ModelPath = Join-Path $ModelDir ([string]$Lock.canonical_model.file)
$ManifestPath = Join-Path $ModelDir "model-7.27.local.json"
$ParentStatePath = Join-Path $ModelWorkDir "parent-download-state.json"

function Test-CanonicalModelPresent {
    if (-not (Test-Path -LiteralPath $ModelPath) -or -not (Test-Path -LiteralPath $ManifestPath)) { return $false }
    try {
        $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
        $bytes = (Get-Item -LiteralPath $ModelPath).Length
        if ($bytes -lt [int64]$Lock.canonical_model.target_min_bytes -or $bytes -gt [int64]$Lock.canonical_model.target_max_bytes) { return $false }
        if ($manifest.schema_version -ne "1.1" -or $manifest.status -ne "CANONICAL_FIXED") { return $false }
        if ($manifest.model_file -ne [string]$Lock.canonical_model.file -or [int64]$manifest.model_bytes -ne $bytes) { return $false }
        if ($manifest.parent_revision -ne [string]$Lock.uncensored_parent.revision -or $manifest.parent_snapshot_verified_complete -ne $true) { return $false }
        $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $ModelPath).Hash.ToLowerInvariant()
        return ([string]$manifest.model_sha256).ToLowerInvariant() -eq $sha
    } catch { return $false }
}

function Test-VerifiedParentState {
    if (-not (Test-Path -LiteralPath $ParentStatePath)) { return $false }
    try {
        $state = Get-Content -Raw -LiteralPath $ParentStatePath | ConvertFrom-Json
        return $state.status -eq "VERIFIED_COMPLETE" -and
            $state.snapshot_complete -eq $true -and
            $state.repo -eq [string]$Lock.uncensored_parent.repo -and
            $state.revision -eq [string]$Lock.uncensored_parent.revision -and
            $state.work_dir -eq $ModelWorkDir
    } catch { return $false }
}

$hasCanonical = Test-CanonicalModelPresent
$parentPrepared = $false
if (-not $PurgeModelDownloadCache -and ($Force -or -not $hasCanonical)) {
    Write-Host "==> Preparing resumable BLACK 7.27 parent snapshot" -ForegroundColor Cyan
    & $Prepare `
        -WorkDir $ModelWorkDir `
        -StallSeconds $ParentStallSeconds `
        -MaxStallRestarts $ParentMaxStallRestarts `
        -RetryBackoffSeconds $ParentRetryBackoffSeconds
    if ($LASTEXITCODE -ne 0) { throw "Parent preload failed with exit code $LASTEXITCODE" }
    if (-not (Test-VerifiedParentState)) { throw "Parent preload returned success without durable VERIFIED_COMPLETE state: $ParentStatePath" }
    $parentPrepared = $true
} elseif ($hasCanonical -and -not $Force) {
    Write-Host "==> Canonical BLACK 7.27 model already verified; parent preload skipped" -ForegroundColor Green
} elseif ($PurgeModelDownloadCache) {
    Write-Host "==> Explicit purge requested; parent preload skipped and canonical setup owns the purge/rebuild path" -ForegroundColor Yellow
}

$args = @{
    ModelWorkDir = $ModelWorkDir
    HfDownloadWorkers = $HfDownloadWorkers
}
if ($Force) { $args.Force = $true }
if ($ForceLlama) { $args.ForceLlama = $true }
if ($PurgeModelDownloadCache) { $args.PurgeModelDownloadCache = $true }

$previousPrepared = $env:BLACK_CODE_PARENT_PREPARED
try {
    if ($parentPrepared) {
        $env:BLACK_CODE_PARENT_PREPARED = "1"
        Write-Host "==> Parent VERIFIED_COMPLETE; canonical builder will validate locally and skip duplicate HF network access" -ForegroundColor Green
    } else {
        Remove-Item Env:BLACK_CODE_PARENT_PREPARED -ErrorAction SilentlyContinue
    }
    Write-Host "==> Entering canonical BLACK Code setup" -ForegroundColor Cyan
    & $Setup @args
    if ($LASTEXITCODE -ne 0) { throw "Canonical setup failed with exit code $LASTEXITCODE" }
} finally {
    if ($null -eq $previousPrepared) { Remove-Item Env:BLACK_CODE_PARENT_PREPARED -ErrorAction SilentlyContinue }
    else { $env:BLACK_CODE_PARENT_PREPARED = $previousPrepared }
}
