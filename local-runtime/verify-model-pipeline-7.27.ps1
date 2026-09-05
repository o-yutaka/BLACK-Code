param(
    [string]$ModelWorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
if (-not (Test-Path -LiteralPath $LockPath)) { throw "model-7.27.lock.json is missing." }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$ModelDir = Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\models"
$ModelPath = Join-Path $ModelDir ([string]$Lock.canonical_model.file)
$ManifestPath = Join-Path $ModelDir "model-7.27.local.json"
$F16Path = Join-Path $ModelWorkDir "uncensored-no-mtp-f16.gguf"
$F16ProvenancePath = "$F16Path.provenance.json"
$TensorMap = Join-Path $ModelWorkDir "tensor-types-7.27.txt"
$TensorEvidencePath = Join-Path $ModelWorkDir "tensor-types-7.27.evidence.json"
$ParentStatePath = Join-Path $ModelWorkDir "parent-download-state.json"

function Test-Gguf([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $bytes = New-Object byte[] 4
        return $stream.Read($bytes,0,4) -eq 4 -and [Text.Encoding]::ASCII.GetString($bytes) -eq "GGUF"
    } finally { $stream.Dispose() }
}

$checks = [ordered]@{}
$checks.model_exists = Test-Path -LiteralPath $ModelPath
$checks.manifest_exists = Test-Path -LiteralPath $ManifestPath
$checks.model_gguf = Test-Gguf $ModelPath
$checks.parent_state_verified = $false
$checks.f16_provenance_consistent = $true
$checks.tensor_evidence_consistent = $true
$checks.size_gate = $false
$checks.sha_match = $false
$checks.manifest_contract = $false

if (Test-Path -LiteralPath $ParentStatePath) {
    try {
        $parent = Get-Content -Raw -LiteralPath $ParentStatePath | ConvertFrom-Json
        $checks.parent_state_verified = $parent.status -eq "VERIFIED_COMPLETE" -and $parent.snapshot_complete -eq $true -and $parent.repo -eq [string]$Lock.uncensored_parent.repo -and $parent.revision -eq [string]$Lock.uncensored_parent.revision
    } catch { $checks.parent_state_verified = $false }
}

if ((Test-Path -LiteralPath $F16Path) -or (Test-Path -LiteralPath $F16ProvenancePath)) {
    try {
        if (-not (Test-Gguf $F16Path) -or -not (Test-Path -LiteralPath $F16ProvenancePath)) { throw "F16/provenance pair incomplete" }
        $fp = Get-Content -Raw -LiteralPath $F16ProvenancePath | ConvertFrom-Json
        $actualBytes = (Get-Item -LiteralPath $F16Path).Length
        $actualSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $F16Path).Hash.ToLowerInvariant()
        $checks.f16_provenance_consistent = [int64]$fp.bytes -eq $actualBytes -and ([string]$fp.sha256).ToLowerInvariant() -eq $actualSha -and $fp.source_repo -eq [string]$Lock.uncensored_parent.repo -and $fp.source_revision -eq [string]$Lock.uncensored_parent.revision -and $fp.converter_revision -eq [string]$Lock.llama_cpp_conversion_source.revision -and $fp.no_mtp -eq $true
    } catch { $checks.f16_provenance_consistent = $false }
}

if ((Test-Path -LiteralPath $TensorMap) -or (Test-Path -LiteralPath $TensorEvidencePath)) {
    try {
        if (-not (Test-Path -LiteralPath $TensorMap) -or -not (Test-Path -LiteralPath $TensorEvidencePath)) { throw "tensor map/evidence pair incomplete" }
        $e = Get-Content -Raw -LiteralPath $TensorEvidencePath | ConvertFrom-Json
        $lines = @(Get-Content -LiteralPath $TensorMap | Where-Object { $_.Trim() })
        $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $TensorMap).Hash.ToLowerInvariant()
        $checks.tensor_evidence_consistent = $e.status -eq "PASS" -and $e.local_f16.names_match_reference -eq $true -and [int64]$e.tensor_map.entries -eq $lines.Count -and ([string]$e.tensor_map.sha256).ToLowerInvariant() -eq $sha
    } catch { $checks.tensor_evidence_consistent = $false }
}

$modelSha = $null
$modelBytes = $null
if ($checks.model_exists) {
    $modelBytes = (Get-Item -LiteralPath $ModelPath).Length
    $checks.size_gate = $modelBytes -ge [int64]$Lock.canonical_model.target_min_bytes -and $modelBytes -le [int64]$Lock.canonical_model.target_max_bytes
    if ($checks.model_gguf) { $modelSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $ModelPath).Hash.ToLowerInvariant() }
}

if ($checks.manifest_exists -and $null -ne $modelSha) {
    try {
        $m = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
        $checks.sha_match = ([string]$m.model_sha256).ToLowerInvariant() -eq $modelSha -and [int64]$m.model_bytes -eq $modelBytes
        $ranges = @($m.quant_map_reference_range_evidence)
        $rangesOk = $ranges.Count -gt 0
        foreach ($range in $ranges) {
            if ([int64]$range.received_bytes -le 0 -or [int64]$range.remote_total_bytes -le [int64]$range.received_bytes -or ([string]$range.sha256) -notmatch '^[0-9a-f]{64}$') { $rangesOk = $false }
        }
        $checks.manifest_contract = $m.schema_version -eq "1.1" -and $m.status -eq "CANONICAL_FIXED" -and $m.model_file -eq [string]$Lock.canonical_model.file -and $m.parent_repo -eq [string]$Lock.uncensored_parent.repo -and $m.parent_revision -eq [string]$Lock.uncensored_parent.revision -and $m.parent_snapshot_verified_complete -eq $true -and $m.no_mtp -eq $true -and $m.vision -eq $false -and ([string]$m.imatrix_sha256).ToLowerInvariant() -eq ([string]$Lock.imatrix.sha256).ToLowerInvariant() -and $m.local_f16_provenance_verified -eq $true -and $m.local_f16_names_match_reference -eq $true -and $m.quantization -eq "BLACK-UD-IQ2_XXS exact-reference-tensor-map" -and $rangesOk
    } catch { $checks.manifest_contract = $false }
}

$required = @('model_exists','manifest_exists','model_gguf','size_gate','sha_match','manifest_contract','f16_provenance_consistent','tensor_evidence_consistent')
$failures = @($required | Where-Object { -not [bool]$checks[$_] })
$result = [ordered]@{
    schema_version = "1.0"
    verified_at = (Get-Date).ToString("o")
    status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
    model_file = [string]$Lock.canonical_model.file
    model_path = $ModelPath
    model_bytes = $modelBytes
    model_sha256 = $modelSha
    checks = $checks
    failures = $failures
}

$text = $result | ConvertTo-Json -Depth 8
if ($Json) { Write-Output $text }
else {
    $color = if ($result.status -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host "BLACK 7.27 MODEL PIPELINE VERIFY: $($result.status)" -ForegroundColor $color
    Write-Host "Model: $ModelPath"
    Write-Host "Bytes: $modelBytes"
    Write-Host "SHA256: $modelSha"
    if ($failures.Count -gt 0) { Write-Host "Failures: $($failures -join ', ')" -ForegroundColor Red }
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
