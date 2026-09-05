param(
    [switch]$Force,
    [switch]$ForceLlama,
    [string]$ModelWorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [switch]$PurgeModelDownloadCache,
    [ValidateRange(1,16)][int]$HfDownloadWorkers = 8,
    [ValidateRange(60,7200)][int]$ParentStallSeconds = 900,
    [ValidateRange(0,20)][int]$ParentMaxStallRestarts = 4,
    [ValidateRange(1,300)][int]$ParentRetryBackoffSeconds = 10,
    [switch]$StatusOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0

$SetupResumable = Join-Path $PSScriptRoot "setup-resumable-7.27.ps1"
$Verifier = Join-Path $PSScriptRoot "verify-model-pipeline-7.27.ps1"
$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
foreach ($required in @($SetupResumable,$Verifier,$LockPath)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required 7.27 pipeline input missing: $required" } }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$StatePath = Join-Path $ModelWorkDir "model-pipeline-state.json"
$ModelDir = Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\models"
$ModelPath = Join-Path $ModelDir ([string]$Lock.canonical_model.file)
$ManifestPath = Join-Path $ModelDir "model-7.27.local.json"
$ParentStatePath = Join-Path $ModelWorkDir "parent-download-state.json"
$F16Path = Join-Path $ModelWorkDir "uncensored-no-mtp-f16.gguf"
$F16ProvenancePath = "$F16Path.provenance.json"
$TensorMap = Join-Path $ModelWorkDir "tensor-types-7.27.txt"
$TensorEvidencePath = Join-Path $ModelWorkDir "tensor-types-7.27.evidence.json"
$TempOutput = "$ModelPath.building"
$DryRunLog = Join-Path $ModelWorkDir "quantize-dry-run.log"

function Get-ArtifactPhase {
    $parentComplete = $false
    if (Test-Path -LiteralPath $ParentStatePath) {
        try { $p = Get-Content -Raw -LiteralPath $ParentStatePath | ConvertFrom-Json; $parentComplete = $p.status -eq "VERIFIED_COMPLETE" -and $p.snapshot_complete -eq $true } catch {}
    }
    $f16 = Test-Path -LiteralPath $F16Path
    $f16Prov = Test-Path -LiteralPath $F16ProvenancePath
    $tensor = (Test-Path -LiteralPath $TensorMap) -and (Test-Path -LiteralPath $TensorEvidencePath)
    $dry = Test-Path -LiteralPath $DryRunLog
    $building = Test-Path -LiteralPath $TempOutput
    $model = Test-Path -LiteralPath $ModelPath
    $manifest = Test-Path -LiteralPath $ManifestPath
    if ($model -and $manifest) { return "MANIFEST_READY" }
    if ($building) { return "QUANTIZATION_INCOMPLETE" }
    if ($dry) { return "DRY_RUN_COMPLETE" }
    if ($tensor) { return "TENSOR_MAP_COMPLETE" }
    if ($f16 -and $f16Prov) { return "F16_VERIFIED" }
    if ($f16 -or $f16Prov) { return "F16_INCOMPLETE" }
    if ($parentComplete) { return "PARENT_VERIFIED" }
    return "PARENT_PENDING"
}

function Write-State([string]$Status,[string]$Detail) {
    New-Item -ItemType Directory -Force -Path $ModelWorkDir | Out-Null
    $modelBytes = if (Test-Path -LiteralPath $ModelPath) { [int64](Get-Item -LiteralPath $ModelPath).Length } else { $null }
    $modelSha = if (Test-Path -LiteralPath $ModelPath) { try { (Get-FileHash -Algorithm SHA256 -LiteralPath $ModelPath).Hash.ToLowerInvariant() } catch { $null } } else { $null }
    $state = [ordered]@{
        schema_version = "1.0"
        updated_at = (Get-Date).ToString("o")
        status = $Status
        phase = Get-ArtifactPhase
        work_dir = $ModelWorkDir
        parent_state = $ParentStatePath
        f16_path = $F16Path
        f16_provenance = $F16ProvenancePath
        tensor_map = $TensorMap
        tensor_evidence = $TensorEvidencePath
        quantize_dry_run_log = $DryRunLog
        quantize_temp_output = $TempOutput
        model_path = $ModelPath
        manifest_path = $ManifestPath
        model_bytes = $modelBytes
        model_sha256 = $modelSha
        detail = $Detail
    }
    $tmp = "$StatePath.tmp-$PID"
    $state | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $tmp
    Move-Item -Force -LiteralPath $tmp -Destination $StatePath
}

if ($StatusOnly) {
    Write-State "STATUS" "Status-only inspection; no build command executed."
    Get-Content -Raw -LiteralPath $StatePath
    exit 0
}

trap {
    try { Write-State "FAILED" $_.Exception.Message } catch {}
    throw
}

Write-State "STARTING" "Governed 7.27 pipeline starting/resuming from durable artifacts."
$args = @{
    ModelWorkDir = $ModelWorkDir
    HfDownloadWorkers = $HfDownloadWorkers
    ParentStallSeconds = $ParentStallSeconds
    ParentMaxStallRestarts = $ParentMaxStallRestarts
    ParentRetryBackoffSeconds = $ParentRetryBackoffSeconds
}
if ($Force) { $args.Force = $true }
if ($ForceLlama) { $args.ForceLlama = $true }
if ($PurgeModelDownloadCache) { $args.PurgeModelDownloadCache = $true }

Write-State "RUNNING" "Executing resumable setup. Parent transfer is watchdog-governed; F16/quantization reuse verified intermediate artifacts."
& $SetupResumable @args
if ($LASTEXITCODE -ne 0) { throw "setup-resumable-7.27.ps1 failed with exit code $LASTEXITCODE" }

Write-State "VERIFYING" "Setup returned success; independently recalculating final GGUF size/SHA and validating manifest/provenance contracts."
& $Verifier -ModelWorkDir $ModelWorkDir
if ($LASTEXITCODE -ne 0) { throw "Independent 7.27 pipeline verification failed with exit code $LASTEXITCODE" }

Write-State "COMPLETE" "F16 conversion, tensor-map evidence, IQ2_XXS artifact, SHA256 and canonical manifest independently verified."
Write-Host "BLACK 7.27 MODEL PIPELINE COMPLETE" -ForegroundColor Green
Write-Host "State: $StatePath"
Write-Host "Model: $ModelPath"
Write-Host "Manifest: $ManifestPath"
