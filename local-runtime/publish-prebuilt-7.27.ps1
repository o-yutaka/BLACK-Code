param(
    [Parameter(Mandatory = $true)][string]$RepoId,
    [string]$Revision = "main",
    [string]$ModelDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\models"),
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:LASTEXITCODE = 0

if ($env:OS -ne "Windows_NT") { throw "publish-prebuilt-7.27.ps1 must run in Windows PowerShell, not WSL/Linux." }

$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
if (-not (Test-Path -LiteralPath $LockPath)) { throw "model-7.27.lock.json is missing." }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$ModelFile = [string]$Lock.canonical_model.file
$ModelPath = Join-Path $ModelDir $ModelFile
$ManifestFile = "model-7.27.local.json"
$ManifestPath = Join-Path $ModelDir $ManifestFile
$Hf = Join-Path $WorkDir ".venv\Scripts\hf.exe"

foreach ($required in @($ModelPath,$ManifestPath,$Hf)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required publish input missing: $required" } }

$bytes = (Get-Item -LiteralPath $ModelPath).Length
$min = [int64]$Lock.canonical_model.target_min_bytes
$max = [int64]$Lock.canonical_model.target_max_bytes
if ($bytes -lt $min -or $bytes -gt $max) { throw "Canonical model outside size window: $bytes bytes" }
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $ModelPath).Hash.ToLowerInvariant()
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($manifest.schema_version -ne "1.1" -or $manifest.status -ne "CANONICAL_FIXED") { throw "Canonical manifest is not publishable" }
if ($manifest.model_file -ne $ModelFile -or [int64]$manifest.model_bytes -ne $bytes -or ([string]$manifest.model_sha256).ToLowerInvariant() -ne $sha) { throw "Canonical manifest does not match the actual GGUF" }
if ($manifest.parent_revision -ne [string]$Lock.uncensored_parent.revision -or $manifest.parent_snapshot_verified_complete -ne $true) { throw "Canonical manifest parent provenance mismatch" }
if ($manifest.local_f16_provenance_verified -ne $true -or $manifest.local_f16_names_match_reference -ne $true) { throw "Canonical manifest F16/tensor provenance is not verified" }
if ($manifest.quantization -ne "BLACK-UD-IQ2_XXS exact-reference-tensor-map") { throw "Canonical manifest quantization contract mismatch" }

Write-Host "Publishing verified BLACK 7.27 artifact to Hugging Face: $RepoId@$Revision" -ForegroundColor Cyan
& $Hf upload $RepoId $ModelPath $ModelFile --revision $Revision
if ($LASTEXITCODE -ne 0) { throw "hf upload model failed with exit code $LASTEXITCODE" }
& $Hf upload $RepoId $ManifestPath $ManifestFile --revision $Revision
if ($LASTEXITCODE -ne 0) { throw "hf upload manifest failed with exit code $LASTEXITCODE" }

$base = "https://huggingface.co/$RepoId/resolve/$Revision"
Write-Host "BLACK 7.27 PREBUILT PUBLISHED" -ForegroundColor Green
Write-Host "Model URL:    $base/$ModelFile?download=true"
Write-Host "Manifest URL: $base/$ManifestFile?download=true"
Write-Host "SHA256:       $sha"
Write-Host "Use these three values with install-prebuilt-7.27.ps1, then run setup.ps1 normally."
