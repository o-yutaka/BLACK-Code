param(
    [string]$ModelDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\models"),
    [string]$LlamaBinDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\llama"),
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [ValidateRange(1,16)][int]$HfDownloadWorkers = 8,
    [switch]$ForceRebuild,
    [switch]$PurgeDownloadCache,
    [switch]$KeepIntermediate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:LASTEXITCODE = 0

$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
$MapExtractor = Join-Path $PSScriptRoot "extract-quant-map.mjs"
$HfDownloader = Join-Path $PSScriptRoot "hf-parallel-download.ps1"
foreach ($required in @($LockPath,$MapExtractor,$HfDownloader)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required 7.27 build input missing: $required" } }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json

$OutputPath = Join-Path $ModelDir $Lock.canonical_model.file
$ManifestPath = Join-Path $ModelDir "model-7.27.local.json"
$DraftPath = Join-Path $ModelDir $Lock.mtp_draft.file
$SourceDir = Join-Path $WorkDir "uncensored-parent"
$LlamaSource = Join-Path $WorkDir "llama.cpp"
$F16Path = Join-Path $WorkDir "uncensored-no-mtp-f16.gguf"
$F16ProvenancePath = "$F16Path.provenance.json"
$TensorMap = Join-Path $WorkDir "tensor-types-7.27.txt"
$TensorEvidencePath = Join-Path $WorkDir "tensor-types-7.27.evidence.json"
$ImatrixPath = Join-Path $WorkDir $Lock.imatrix.file
$TempOutput = "$OutputPath.building"
$VenvDir = Join-Path $WorkDir ".venv"

function Require-Command([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required command missing: $Name" }
    return $command.Source
}
function Invoke-Native([string]$File,[string[]]$Arguments,[string]$Label) {
    Write-Host "[7.27] $Label" -ForegroundColor Cyan
    & $File @Arguments
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    if ($code -ne 0) { throw "$Label failed with exit code $code" }
}
function Assert-Sha([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label missing: $Path" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$Expected).ToLowerInvariant()) { throw "$Label SHA256 mismatch: $actual != $Expected" }
}
function Assert-Gguf([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try { $bytes = New-Object byte[] 4; if ($stream.Read($bytes,0,4) -ne 4 -or [Text.Encoding]::ASCII.GetString($bytes) -ne "GGUF") { throw "Not a GGUF file: $Path" } }
    finally { $stream.Dispose() }
}
function Get-HelpText([string]$Exe) {
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList @("--help") -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        return ((Get-Content -Raw -LiteralPath $out -ErrorAction SilentlyContinue) + "`n" + (Get-Content -Raw -LiteralPath $err -ErrorAction SilentlyContinue))
    } finally { Remove-Item -Force -ErrorAction SilentlyContinue $out,$err }
}
function Get-HfUrl([object]$Spec) {
    return "https://huggingface.co/" + [string]$Spec.repo + "/resolve/" + [string]$Spec.revision + "/" + [string]$Spec.file + "?download=true"
}
function Get-DirectoryBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0L }
    $sum = 0L
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $sum += [int64]$_.Length }
    return $sum
}
function Assert-HfSnapshotComplete([string]$Path) {
    $config = Join-Path $Path "config.json"
    if (-not (Test-Path -LiteralPath $config)) { throw "Parent snapshot incomplete: config.json missing after hf download." }
    $indexPath = Join-Path $Path "model.safetensors.index.json"
    if (Test-Path -LiteralPath $indexPath) {
        $index = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
        $shards = @($index.weight_map.PSObject.Properties | ForEach-Object { [string]$_.Value } | Sort-Object -Unique)
        if ($shards.Count -lt 1) { throw "Parent snapshot index contains no safetensor shards." }
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($shard in $shards) {
            $shardPath = Join-Path $Path $shard
            if (-not (Test-Path -LiteralPath $shardPath) -or (Get-Item -LiteralPath $shardPath).Length -le 0) { [void]$missing.Add($shard) }
        }
        if ($missing.Count -gt 0) { throw "Parent snapshot incomplete after hf download; missing/empty shards: $([string]::Join(', ', @($missing | Select-Object -First 20)))" }
        Write-Host "[7.27] parent snapshot complete: $($shards.Count) safetensor shards" -ForegroundColor Green
        return
    }
    $single = @(Get-ChildItem -LiteralPath $Path -Filter "*.safetensors" -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
    if ($single.Count -lt 1) { throw "Parent snapshot incomplete: no safetensors files found after hf download." }
    Write-Host "[7.27] parent snapshot complete: $($single.Count) safetensors file(s)" -ForegroundColor Green
}
function Test-ExistingCanonical {
    if (-not (Test-Path -LiteralPath $OutputPath) -or -not (Test-Path -LiteralPath $ManifestPath)) { return $false }
    try {
        $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
        $bytes = (Get-Item -LiteralPath $OutputPath).Length
        if ($bytes -lt [int64]$Lock.canonical_model.target_min_bytes -or $bytes -gt [int64]$Lock.canonical_model.target_max_bytes) { return $false }
        $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath).Hash.ToLowerInvariant()
        return $manifest.model_sha256 -eq $sha -and $manifest.model_file -eq $Lock.canonical_model.file -and $manifest.parent_revision -eq $Lock.uncensored_parent.revision
    } catch { return $false }
}

if ($env:OS -ne "Windows_NT") { throw "The canonical BLACK Code 7.27 builder is currently Windows-only." }
New-Item -ItemType Directory -Force -Path $ModelDir,$WorkDir | Out-Null
if (-not $ForceRebuild -and (Test-ExistingCanonical)) {
    Write-Host "BLACK 7.27 canonical model already matches its local manifest." -ForegroundColor Green
    return
}

$Node = Require-Command "node.exe"
$Python = Require-Command "python.exe"
$Git = Require-Command "git.exe"
$Quantize = Join-Path $LlamaBinDir "llama-quantize.exe"
if (-not (Test-Path -LiteralPath $Quantize)) { throw "llama-quantize.exe missing: $Quantize. Run BLACK Code setup with the current llama.cpp package first." }
$quantHelp = Get-HelpText $Quantize
if (-not $quantHelp.Contains([string]$Lock.llama_cpp_conversion_source.required_quantizer_flag)) { throw "Installed llama-quantize does not support --tensor-type-file. Update BLACK Code llama.cpp first." }
$QuantizerVersion = (& $Quantize --version 2>&1 | Out-String).Trim()

$root = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $WorkDir).Path)
$drive = [IO.DriveInfo]::new($root)
$RequiredPeakBytes = 125000000000L
$ReusableWorkBytes = if ($PurgeDownloadCache) { 0L } else { Get-DirectoryBytes $SourceDir }
$EffectiveBuildCapacity = [int64]$drive.AvailableFreeSpace + [int64]$ReusableWorkBytes
if ($EffectiveBuildCapacity -lt $RequiredPeakBytes) {
    throw ("7.27 build needs at least 125 GB effective working capacity (free + resumable parent cache); free={0:N1} GiB reusable={1:N1} GiB on {2}" -f ($drive.AvailableFreeSpace/1GB),($ReusableWorkBytes/1GB),$root)
}
Write-Host ("[7.27] disk preflight: free={0:N1} GiB reusable-parent={1:N1} GiB effective={2:N1} GiB" -f ($drive.AvailableFreeSpace/1GB),($ReusableWorkBytes/1GB),($EffectiveBuildCapacity/1GB))

if (-not (Test-Path -LiteralPath (Join-Path $VenvDir "Scripts\python.exe"))) {
    Invoke-Native $Python @("-m","venv",$VenvDir) "create build venv"
}
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
Invoke-Native $VenvPython @("-m","pip","install","--disable-pip-version-check","--upgrade","pip") "update build pip"
Invoke-Native $VenvPython @("-m","pip","install","--disable-pip-version-check","huggingface_hub[hf_xet]") "install HF/Xet transport"
$Hf = Join-Path $VenvDir "Scripts\hf.exe"
if (-not (Test-Path -LiteralPath $Hf)) { throw "hf CLI was not installed in build venv." }
$HfHubVersion = (& $VenvPython -c "import huggingface_hub; print(huggingface_hub.__version__)" | Select-Object -First 1).Trim()

if ($PurgeDownloadCache -and (Test-Path -LiteralPath $SourceDir)) {
    Write-Host "[7.27] PURGE requested: removing parent snapshot/cache before download" -ForegroundColor Yellow
    Remove-Item -Recurse -Force $SourceDir
}
$previousXet = $env:HF_XET_HIGH_PERFORMANCE
$previousTimeout = $env:HF_HUB_DOWNLOAD_TIMEOUT
$env:HF_XET_HIGH_PERFORMANCE = "1"
$env:HF_HUB_DOWNLOAD_TIMEOUT = "600"
try {
    # Always invoke the pinned hf download. It is the resume/integrity step: completed files are reused,
    # .incomplete files are resumed, and a stale config.json alone can never mark the snapshot complete.
    Invoke-Native $Hf @("download",[string]$Lock.uncensored_parent.repo,"--revision",[string]$Lock.uncensored_parent.revision,"--local-dir",$SourceDir) "resume/validate parallel HF/Xet parent snapshot"
} finally {
    if ($null -eq $previousXet) { Remove-Item Env:HF_XET_HIGH_PERFORMANCE -ErrorAction SilentlyContinue } else { $env:HF_XET_HIGH_PERFORMANCE = $previousXet }
    if ($null -eq $previousTimeout) { Remove-Item Env:HF_HUB_DOWNLOAD_TIMEOUT -ErrorAction SilentlyContinue } else { $env:HF_HUB_DOWNLOAD_TIMEOUT = $previousTimeout }
}
Assert-HfSnapshotComplete $SourceDir

if (-not (Test-Path -LiteralPath (Join-Path $LlamaSource ".git"))) {
    New-Item -ItemType Directory -Force -Path $LlamaSource | Out-Null
    Invoke-Native $Git @("-C",$LlamaSource,"init") "initialize pinned llama.cpp source"
    Invoke-Native $Git @("-C",$LlamaSource,"remote","add","origin",[string]$Lock.llama_cpp_conversion_source.repo) "add llama.cpp origin"
}
Invoke-Native $Git @("-C",$LlamaSource,"fetch","--depth=1","origin",[string]$Lock.llama_cpp_conversion_source.revision) "fetch pinned llama.cpp conversion source"
Invoke-Native $Git @("-C",$LlamaSource,"checkout","--detach","FETCH_HEAD") "checkout pinned llama.cpp conversion source"
$Requirements = Join-Path $LlamaSource "requirements\requirements-convert_hf_to_gguf.txt"
Invoke-Native $VenvPython @("-m","pip","install","--disable-pip-version-check","-r",$Requirements) "install pinned converter requirements"

if ($ForceRebuild) { Remove-Item -Force -ErrorAction SilentlyContinue $F16Path,$F16ProvenancePath }
if (-not (Test-Path -LiteralPath $F16Path)) {
    $freeBeforeF16 = [IO.DriveInfo]::new($root).AvailableFreeSpace
    $MinFreeBeforeF16 = 60000000000L
    if ($freeBeforeF16 -lt $MinFreeBeforeF16) {
        throw ("Not enough free space to safely create the F16 intermediate; need >=60 GB free after parent completion, available={0:N1} GiB. Parent cache is preserved for resume." -f ($freeBeforeF16/1GB))
    }
    $Converter = Join-Path $LlamaSource "convert_hf_to_gguf.py"
    Invoke-Native $VenvPython @($Converter,$SourceDir,"--outfile",$F16Path,"--outtype","f16","--no-mtp") "convert pinned uncensored parent to no-MTP F16 GGUF"
    Assert-Gguf $F16Path
    $F16Bytes = (Get-Item -LiteralPath $F16Path).Length
    $F16Sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $F16Path).Hash.ToLowerInvariant()
    [ordered]@{
        schema_version = "1.0"
        source_repo = [string]$Lock.uncensored_parent.repo
        source_revision = [string]$Lock.uncensored_parent.revision
        converter_repo = [string]$Lock.llama_cpp_conversion_source.repo
        converter_revision = [string]$Lock.llama_cpp_conversion_source.revision
        outtype = "f16"
        no_mtp = $true
        file = [IO.Path]::GetFileName($F16Path)
        bytes = $F16Bytes
        sha256 = $F16Sha
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath $F16ProvenancePath
}
Assert-Gguf $F16Path
if ((Get-Item -LiteralPath $F16Path).Length -le 0) { throw "F16 intermediate is empty: $F16Path" }
if (-not (Test-Path -LiteralPath $F16ProvenancePath)) { throw "F16 provenance is missing; rerun with -ForceRebuild to regenerate from the pinned parent." }
$F16Provenance = Get-Content -Raw -LiteralPath $F16ProvenancePath | ConvertFrom-Json
if ($F16Provenance.source_repo -ne [string]$Lock.uncensored_parent.repo -or $F16Provenance.source_revision -ne [string]$Lock.uncensored_parent.revision -or $F16Provenance.converter_revision -ne [string]$Lock.llama_cpp_conversion_source.revision -or -not $F16Provenance.no_mtp) {
    throw "F16 provenance does not match the pinned 7.27 build inputs; rerun with -ForceRebuild."
}
if ([int64]$F16Provenance.bytes -ne (Get-Item -LiteralPath $F16Path).Length) { throw "F16 provenance byte count mismatch" }
Assert-Sha $F16Path ([string]$F16Provenance.sha256) "F16 provenance"
if (-not $KeepIntermediate -and (Test-Path -LiteralPath $SourceDir)) {
    Remove-Item -Recurse -Force $SourceDir
    Write-Host "[7.27] removed parent snapshot after verified F16 conversion to release disk space"
}

if (-not (Test-Path -LiteralPath $ImatrixPath) -or $ForceRebuild) {
    if (Test-Path -LiteralPath $ImatrixPath) { Remove-Item -Force $ImatrixPath }
    & $HfDownloader -Url (Get-HfUrl $Lock.imatrix) -Destination $ImatrixPath -Workers $HfDownloadWorkers
    if ($LASTEXITCODE -ne 0) { throw "imatrix download failed with exit code $LASTEXITCODE" }
}
Assert-Sha $ImatrixPath $Lock.imatrix.sha256 "Uncensored imatrix"

$ReferenceUrl = Get-HfUrl $Lock.quant_map_reference
Remove-Item -Force -ErrorAction SilentlyContinue $TensorEvidencePath
Invoke-Native $Node @($MapExtractor,$ReferenceUrl,$TensorMap,$F16Path,$TensorEvidencePath) "extract pinned 7.27 tensor map and assert tensor inventory"
if (-not (Test-Path -LiteralPath $TensorMap)) { throw "tensor type map was not generated" }
if (-not (Test-Path -LiteralPath $TensorEvidencePath)) { throw "tensor map Range evidence was not generated" }
$mapLines = @(Get-Content -LiteralPath $TensorMap | Where-Object { $_.Trim() })
if ($mapLines.Count -lt 100) { throw "tensor type map is unexpectedly small: $($mapLines.Count) entries" }
$TensorEvidence = Get-Content -Raw -LiteralPath $TensorEvidencePath | ConvertFrom-Json
if ($TensorEvidence.status -ne "PASS" -or -not $TensorEvidence.local_f16.names_match_reference) { throw "tensor inventory evidence did not pass" }
if ([int64]$TensorEvidence.reference.tensor_count -ne $mapLines.Count -or [int64]$TensorEvidence.tensor_map.entries -ne $mapLines.Count) { throw "tensor evidence count does not match generated map" }
if ($TensorEvidence.reference.full_reference_downloaded -or $TensorEvidence.reference.full_reference_sha256_measured) { throw "Range-only reference evidence flags are inconsistent" }
$MeasuredMapSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $TensorMap).Hash.ToLowerInvariant()
if ($MeasuredMapSha -ne [string]$TensorEvidence.tensor_map.sha256) { throw "tensor map SHA256 does not match extractor evidence" }
$MeasuredRanges = @($TensorEvidence.reference.fetched_ranges)
if ($MeasuredRanges.Count -lt 1) { throw "no measured reference Range evidence was recorded" }
foreach ($range in $MeasuredRanges) {
    if ([int64]$range.received_bytes -le 0 -or [int64]$range.remote_total_bytes -le [int64]$range.received_bytes -or ([string]$range.sha256) -notmatch '^[0-9a-f]{64}$' -or ([string]$range.content_range) -notmatch '^bytes 0-[0-9]+/[0-9]+$') {
        throw "invalid measured reference Range evidence"
    }
}

Remove-Item -Force -ErrorAction SilentlyContinue $TempOutput
$DryRunLog = Join-Path $WorkDir "quantize-dry-run.log"
Write-Host "[7.27] llama-quantize dry-run" -ForegroundColor Cyan
& $Quantize --imatrix $ImatrixPath --tensor-type-file $TensorMap --dry-run $F16Path $TempOutput IQ2_XXS 2>&1 | Tee-Object -FilePath $DryRunLog
if ($LASTEXITCODE -ne 0) { throw "llama-quantize dry-run failed with exit code $LASTEXITCODE" }

Write-Host "[7.27] quantizing BLACK canonical model" -ForegroundColor Cyan
& $Quantize --imatrix $ImatrixPath --tensor-type-file $TensorMap $F16Path $TempOutput IQ2_XXS
if ($LASTEXITCODE -ne 0) { throw "llama-quantize failed with exit code $LASTEXITCODE" }
Assert-Gguf $TempOutput
$OutputBytes = (Get-Item -LiteralPath $TempOutput).Length
$MinBytes = [int64]$Lock.canonical_model.target_min_bytes
$MaxBytes = [int64]$Lock.canonical_model.target_max_bytes
if ($OutputBytes -lt $MinBytes -or $OutputBytes -gt $MaxBytes) {
    throw "BLACK 7.27 build outside canonical size window: $OutputBytes bytes, expected $MinBytes..$MaxBytes"
}
$OutputSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $TempOutput).Hash.ToLowerInvariant()
Move-Item -Force -LiteralPath $TempOutput -Destination $OutputPath

$manifest = [ordered]@{
    schema_version = "1.1"
    status = "CANONICAL_FIXED"
    built_at = (Get-Date).ToString("o")
    model_file = [string]$Lock.canonical_model.file
    model_sha256 = $OutputSha
    model_bytes = $OutputBytes
    model_size_decimal_gb = [Math]::Round($OutputBytes / 1e9, 4)
    no_mtp = $true
    vision = $false
    parent_repo = [string]$Lock.uncensored_parent.repo
    parent_revision = [string]$Lock.uncensored_parent.revision
    parent_snapshot_verified_complete = $true
    quant_map_reference_repo = [string]$Lock.quant_map_reference.repo
    quant_map_reference_revision = [string]$Lock.quant_map_reference.revision
    quant_map_reference_expected_full_sha256 = [string]$Lock.quant_map_reference.sha256
    quant_map_reference_full_sha256_measured = $false
    quant_map_reference_full_downloaded = $false
    quant_map_reference_range_evidence = @($MeasuredRanges | ForEach-Object {
        [ordered]@{ content_range = [string]$_.content_range; received_bytes = [int64]$_.received_bytes; remote_total_bytes = [int64]$_.remote_total_bytes; sha256 = [string]$_.sha256; etag = [string]$_.etag; resolved_url = [string]$_.resolved_url }
    })
    imatrix_sha256 = [string]$Lock.imatrix.sha256
    tensor_map_entries = $mapLines.Count
    tensor_map_sha256 = [string]$TensorEvidence.tensor_map.sha256
    reference_tensor_inventory_sha256 = [string]$TensorEvidence.reference.tensor_inventory_sha256
    local_f16_bytes = [int64]$TensorEvidence.local_f16.bytes
    local_f16_sha256 = [string]$F16Provenance.sha256
    local_f16_provenance_verified = $true
    local_f16_tensor_count = [int64]$TensorEvidence.local_f16.tensor_count
    local_f16_tensor_inventory_sha256 = [string]$TensorEvidence.local_f16.tensor_inventory_sha256
    local_f16_names_match_reference = [bool]$TensorEvidence.local_f16.names_match_reference
    llama_conversion_revision = [string]$Lock.llama_cpp_conversion_source.revision
    quantizer_version = $QuantizerVersion
    huggingface_hub_version = $HfHubVersion
    hf_parent_transport = "hf_xet_high_performance_resume_validated"
    quantization = "BLACK-UD-IQ2_XXS exact-reference-tensor-map"
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $ManifestPath

if (-not $KeepIntermediate) {
    Remove-Item -Force -ErrorAction SilentlyContinue $F16Path,$F16ProvenancePath,$ImatrixPath,$TensorMap,$TensorEvidencePath,$DryRunLog
}
Write-Host "BLACK 7.27 MODEL BUILT AND PINNED LOCALLY" -ForegroundColor Green
Write-Host "Model:  $OutputPath"
Write-Host "Bytes:  $OutputBytes"
Write-Host "SHA256: $OutputSha"
Write-Host "Manifest: $ManifestPath"
