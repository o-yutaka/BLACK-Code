param(
    [string]$ModelDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\models"),
    [string]$LlamaBinDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime\llama"),
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [ValidateRange(1,16)][int]$HfDownloadWorkers = 8,
    [switch]$ForceRebuild,
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
$TensorMap = Join-Path $WorkDir "tensor-types-7.27.txt"
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
    return "https://huggingface.co/$($Spec.repo)/resolve/$($Spec.revision)/$($Spec.file)?download=true"
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
$RequiredFree = 125000000000L
if ($drive.AvailableFreeSpace -lt $RequiredFree) { throw ("7.27 build needs at least 125 GB free working space; available={0:N1} GB on {1}" -f ($drive.AvailableFreeSpace/1GB),$root) }

if (-not (Test-Path -LiteralPath (Join-Path $VenvDir "Scripts\python.exe"))) {
    Invoke-Native $Python @("-m","venv",$VenvDir) "create build venv"
}
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
Invoke-Native $VenvPython @("-m","pip","install","--disable-pip-version-check","--upgrade","pip") "update build pip"
Invoke-Native $VenvPython @("-m","pip","install","--disable-pip-version-check","huggingface_hub[hf_xet]") "install HF/Xet transport"
$Hf = Join-Path $VenvDir "Scripts\hf.exe"
if (-not (Test-Path -LiteralPath $Hf)) { throw "hf CLI was not installed in build venv." }
$HfHubVersion = (& $VenvPython -c "import huggingface_hub; print(huggingface_hub.__version__)" | Select-Object -First 1).Trim()

$previousXet = $env:HF_XET_HIGH_PERFORMANCE
$previousTimeout = $env:HF_HUB_DOWNLOAD_TIMEOUT
$env:HF_XET_HIGH_PERFORMANCE = "1"
$env:HF_HUB_DOWNLOAD_TIMEOUT = "600"
try {
    if ($ForceRebuild -and (Test-Path -LiteralPath $SourceDir)) { Remove-Item -Recurse -Force $SourceDir }
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir "config.json"))) {
        Invoke-Native $Hf @("download",[string]$Lock.uncensored_parent.repo,"--revision",[string]$Lock.uncensored_parent.revision,"--local-dir",$SourceDir) "parallel HF/Xet parent snapshot"
    }
} finally {
    if ($null -eq $previousXet) { Remove-Item Env:HF_XET_HIGH_PERFORMANCE -ErrorAction SilentlyContinue } else { $env:HF_XET_HIGH_PERFORMANCE = $previousXet }
    if ($null -eq $previousTimeout) { Remove-Item Env:HF_HUB_DOWNLOAD_TIMEOUT -ErrorAction SilentlyContinue } else { $env:HF_HUB_DOWNLOAD_TIMEOUT = $previousTimeout }
}

if (-not (Test-Path -LiteralPath (Join-Path $LlamaSource ".git"))) {
    New-Item -ItemType Directory -Force -Path $LlamaSource | Out-Null
    Invoke-Native $Git @("-C",$LlamaSource,"init") "initialize pinned llama.cpp source"
    Invoke-Native $Git @("-C",$LlamaSource,"remote","add","origin",[string]$Lock.llama_cpp_conversion_source.repo) "add llama.cpp origin"
}
Invoke-Native $Git @("-C",$LlamaSource,"fetch","--depth=1","origin",[string]$Lock.llama_cpp_conversion_source.revision) "fetch pinned llama.cpp conversion source"
Invoke-Native $Git @("-C",$LlamaSource,"checkout","--detach","FETCH_HEAD") "checkout pinned llama.cpp conversion source"
$Requirements = Join-Path $LlamaSource "requirements\requirements-convert_hf_to_gguf.txt"
Invoke-Native $VenvPython @("-m","pip","install","--disable-pip-version-check","-r",$Requirements) "install pinned converter requirements"

if ($ForceRebuild -and (Test-Path -LiteralPath $F16Path)) { Remove-Item -Force $F16Path }
if (-not (Test-Path -LiteralPath $F16Path)) {
    $Converter = Join-Path $LlamaSource "convert_hf_to_gguf.py"
    Invoke-Native $VenvPython @($Converter,$SourceDir,"--outfile",$F16Path,"--outtype","f16","--no-mtp") "convert pinned uncensored parent to no-MTP F16 GGUF"
    Assert-Gguf $F16Path
}
if (-not $KeepIntermediate -and (Test-Path -LiteralPath $SourceDir)) {
    Remove-Item -Recurse -Force $SourceDir
    Write-Host "[7.27] removed parent snapshot after F16 conversion to release disk space"
}

if (-not (Test-Path -LiteralPath $ImatrixPath) -or $ForceRebuild) {
    if (Test-Path -LiteralPath $ImatrixPath) { Remove-Item -Force $ImatrixPath }
    & $HfDownloader -Url (Get-HfUrl $Lock.imatrix) -Destination $ImatrixPath -Workers $HfDownloadWorkers
    if ($LASTEXITCODE -ne 0) { throw "imatrix download failed with exit code $LASTEXITCODE" }
}
Assert-Sha $ImatrixPath $Lock.imatrix.sha256 "Uncensored imatrix"

$ReferenceUrl = Get-HfUrl $Lock.quant_map_reference
Invoke-Native $Node @($MapExtractor,$ReferenceUrl,$TensorMap,$F16Path) "extract pinned 7.27 tensor map and assert tensor inventory"
if (-not (Test-Path -LiteralPath $TensorMap)) { throw "tensor type map was not generated" }
$mapLines = @(Get-Content -LiteralPath $TensorMap | Where-Object { $_.Trim() })
if ($mapLines.Count -lt 100) { throw "tensor type map is unexpectedly small: $($mapLines.Count) entries" }

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
    schema_version = "1.0"
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
    quant_map_reference_repo = [string]$Lock.quant_map_reference.repo
    quant_map_reference_revision = [string]$Lock.quant_map_reference.revision
    quant_map_reference_sha256 = [string]$Lock.quant_map_reference.sha256
    imatrix_sha256 = [string]$Lock.imatrix.sha256
    tensor_map_entries = $mapLines.Count
    llama_conversion_revision = [string]$Lock.llama_cpp_conversion_source.revision
    quantizer_version = $QuantizerVersion
    huggingface_hub_version = $HfHubVersion
    hf_parent_transport = "hf_xet_high_performance"
    quantization = "BLACK-UD-IQ2_XXS exact-reference-tensor-map"
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $ManifestPath

if (-not $KeepIntermediate) {
    Remove-Item -Force -ErrorAction SilentlyContinue $F16Path,$ImatrixPath,$TensorMap,$DryRunLog
}
Write-Host "BLACK 7.27 MODEL BUILT AND PINNED LOCALLY" -ForegroundColor Green
Write-Host "Model:  $OutputPath"
Write-Host "Bytes:  $OutputBytes"
Write-Host "SHA256: $OutputSha"
Write-Host "Manifest: $ManifestPath"
