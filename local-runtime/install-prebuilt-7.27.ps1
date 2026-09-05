param(
    [Parameter(Mandatory = $true)][string]$ModelUrl,
    [Parameter(Mandatory = $true)][string]$ManifestUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedSha256,
    [string]$ModelDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\models"),
    [ValidateRange(1,16)][int]$Workers = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:LASTEXITCODE = 0

if ($env:OS -ne "Windows_NT") { throw "install-prebuilt-7.27.ps1 must run in Windows PowerShell, not WSL/Linux." }

$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
$Downloader = Join-Path $PSScriptRoot "hf-parallel-download.ps1"
foreach ($required in @($LockPath,$Downloader)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required prebuilt installer input missing: $required" } }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$ModelFile = [string]$Lock.canonical_model.file
$ModelPath = Join-Path $ModelDir $ModelFile
$ManifestPath = Join-Path $ModelDir "model-7.27.local.json"
$StageDir = Join-Path $ModelDir ".prebuilt-7.27-stage"
$StageModel = Join-Path $StageDir $ModelFile
$StageManifest = Join-Path $StageDir "model-7.27.local.json"

function Assert-Gguf([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "GGUF missing: $Path" }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $bytes = New-Object byte[] 4
        if ($stream.Read($bytes,0,4) -ne 4 -or [Text.Encoding]::ASCII.GetString($bytes) -ne "GGUF") { throw "Not a GGUF file: $Path" }
    } finally { $stream.Dispose() }
}

function Assert-Manifest([object]$Manifest,[int64]$MeasuredBytes,[string]$MeasuredSha) {
    if ($Manifest.schema_version -ne "1.1") { throw "Prebuilt manifest schema_version must be 1.1" }
    if ($Manifest.status -ne "CANONICAL_FIXED") { throw "Prebuilt manifest status is not CANONICAL_FIXED" }
    if ($Manifest.model_file -ne $ModelFile) { throw "Prebuilt manifest model_file mismatch" }
    if ([int64]$Manifest.model_bytes -ne $MeasuredBytes) { throw "Prebuilt manifest byte count mismatch" }
    if (([string]$Manifest.model_sha256).ToLowerInvariant() -ne $MeasuredSha) { throw "Prebuilt manifest SHA mismatch" }
    if ($Manifest.no_mtp -ne $true -or $Manifest.vision -ne $false) { throw "Prebuilt manifest main-model flags mismatch" }
    if ($Manifest.parent_repo -ne [string]$Lock.uncensored_parent.repo) { throw "Prebuilt manifest parent repo mismatch" }
    if ($Manifest.parent_revision -ne [string]$Lock.uncensored_parent.revision) { throw "Prebuilt manifest parent revision mismatch" }
    if ($Manifest.parent_snapshot_verified_complete -ne $true) { throw "Prebuilt manifest lacks verified parent completeness" }
    if ($Manifest.quant_map_reference_repo -ne [string]$Lock.quant_map_reference.repo -or $Manifest.quant_map_reference_revision -ne [string]$Lock.quant_map_reference.revision) { throw "Prebuilt manifest quant-map reference mismatch" }
    if (([string]$Manifest.quant_map_reference_expected_full_sha256).ToLowerInvariant() -ne ([string]$Lock.quant_map_reference.sha256).ToLowerInvariant()) { throw "Prebuilt manifest reference SHA mismatch" }
    if (([string]$Manifest.imatrix_sha256).ToLowerInvariant() -ne ([string]$Lock.imatrix.sha256).ToLowerInvariant()) { throw "Prebuilt manifest imatrix SHA mismatch" }
    if ([int64]$Manifest.tensor_map_entries -lt 100) { throw "Prebuilt manifest tensor-map evidence is unexpectedly small" }
    if (([string]$Manifest.tensor_map_sha256) -notmatch '^[0-9a-f]{64}$') { throw "Prebuilt manifest tensor-map SHA missing" }
    if (([string]$Manifest.reference_tensor_inventory_sha256) -notmatch '^[0-9a-f]{64}$') { throw "Prebuilt manifest reference tensor inventory SHA missing" }
    if ([int64]$Manifest.local_f16_bytes -le 0 -or ([string]$Manifest.local_f16_sha256) -notmatch '^[0-9a-f]{64}$') { throw "Prebuilt manifest F16 provenance missing" }
    if ($Manifest.local_f16_provenance_verified -ne $true -or $Manifest.local_f16_names_match_reference -ne $true) { throw "Prebuilt manifest F16 provenance did not pass" }
    if ($Manifest.local_f16_tensor_inventory_sha256 -ne $Manifest.reference_tensor_inventory_sha256) { throw "Prebuilt manifest tensor inventory mismatch" }
    if ($Manifest.llama_conversion_revision -ne [string]$Lock.llama_cpp_conversion_source.revision) { throw "Prebuilt manifest converter revision mismatch" }
    if ($Manifest.quantization -ne "BLACK-UD-IQ2_XXS exact-reference-tensor-map") { throw "Prebuilt manifest quantization contract mismatch" }
    $ranges = @($Manifest.quant_map_reference_range_evidence)
    if ($ranges.Count -lt 1) { throw "Prebuilt manifest has no reference Range evidence" }
    foreach ($range in $ranges) {
        if ([int64]$range.received_bytes -le 0 -or [int64]$range.remote_total_bytes -le [int64]$range.received_bytes -or ([string]$range.sha256) -notmatch '^[0-9a-f]{64}$' -or ([string]$range.content_range) -notmatch '^bytes 0-[0-9]+/[0-9]+$') {
            throw "Prebuilt manifest contains invalid reference Range evidence"
        }
    }
}

New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null
if (Test-Path -LiteralPath $StageDir) { Remove-Item -Recurse -Force $StageDir }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
try {
    Write-Host "Downloading BLACK 7.27 prebuilt GGUF with resumable range transport" -ForegroundColor Cyan
    & $Downloader -Url $ModelUrl -Destination $StageModel -Workers $Workers
    if ($LASTEXITCODE -ne 0) { throw "Prebuilt model download failed with exit code $LASTEXITCODE" }
    Write-Host "Downloading BLACK 7.27 canonical manifest" -ForegroundColor Cyan
    & $Downloader -Url $ManifestUrl -Destination $StageManifest -Workers 1
    if ($LASTEXITCODE -ne 0) { throw "Prebuilt manifest download failed with exit code $LASTEXITCODE" }

    Assert-Gguf $StageModel
    $bytes = (Get-Item -LiteralPath $StageModel).Length
    $min = [int64]$Lock.canonical_model.target_min_bytes
    $max = [int64]$Lock.canonical_model.target_max_bytes
    if ($bytes -lt $min -or $bytes -gt $max) { throw "Prebuilt model outside canonical size window: $bytes bytes, expected $min..$max" }
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $StageModel).Hash.ToLowerInvariant()
    if ($sha -ne $ExpectedSha256.ToLowerInvariant()) { throw "Prebuilt model SHA256 mismatch: $sha != $($ExpectedSha256.ToLowerInvariant())" }
    $manifest = Get-Content -Raw -LiteralPath $StageManifest | ConvertFrom-Json
    Assert-Manifest $manifest $bytes $sha

    Move-Item -Force -LiteralPath $StageModel -Destination $ModelPath
    Move-Item -Force -LiteralPath $StageManifest -Destination $ManifestPath
    Write-Host "BLACK 7.27 PREBUILT MODEL INSTALLED AND VERIFIED" -ForegroundColor Green
    Write-Host "Model:    $ModelPath"
    Write-Host "Bytes:    $bytes"
    Write-Host "SHA256:   $sha"
    Write-Host "Manifest: $ManifestPath"
    Write-Host "Next: run setup.ps1 normally; Test-CanonicalModel should skip source rebuild."
} finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $StageDir
}
