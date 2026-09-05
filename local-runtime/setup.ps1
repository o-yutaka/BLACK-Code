param(
    [switch]$Force,
    [switch]$ForceLlama,
    [ValidateRange(1, 16)][int]$HfDownloadWorkers = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:LASTEXITCODE = 0

$InstallBase = Join-Path $env:LOCALAPPDATA "BLACK-Code"
$RuntimeDir = Join-Path $InstallBase "runtime"
$LauncherDir = Join-Path $InstallBase "launcher"
$BinDir = Join-Path $InstallBase "bin"
$LlamaDir = Join-Path $RuntimeDir "llama"
$ModelDir = Join-Path $RuntimeDir "models"
$DownloadDir = Join-Path $RuntimeDir "downloads"
$LogDir = Join-Path $RuntimeDir "logs"

$ModelLockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
if (-not (Test-Path -LiteralPath $ModelLockPath)) { throw "model-7.27.lock.json is missing." }
$ModelLock = Get-Content -Raw -LiteralPath $ModelLockPath | ConvertFrom-Json
$ModelFile = [string]$ModelLock.canonical_model.file
$ModelPath = Join-Path $ModelDir $ModelFile
$ModelManifestPath = Join-Path $ModelDir "model-7.27.local.json"
$DraftFile = [string]$ModelLock.mtp_draft.file
$DraftPath = Join-Path $ModelDir $DraftFile
$DraftUrl = "https://huggingface.co/$($ModelLock.mtp_draft.repo)/resolve/$($ModelLock.mtp_draft.revision)/$DraftFile?download=true"
$DraftSha256 = [string]$ModelLock.mtp_draft.sha256
$LegacyModelPaths = @(
    (Join-Path $ModelDir "Qwen3.8-27B-Uncensored-IQ2_M.gguf"),
    (Join-Path $ModelDir "Qwen3.8-27B-Uncensored-IQ4_XS.gguf")
)

function Write-Step([string]$Message) { Write-Host ""; Write-Host "==> $Message" -ForegroundColor Cyan }
function Invoke-NvidiaSmi([string]$Query) {
    $stdout=[IO.Path]::GetTempFileName(); $stderr=[IO.Path]::GetTempFileName()
    try {
        $process=Start-Process -FilePath (Get-Command "nvidia-smi.exe").Source -ArgumentList "--query-gpu=$Query", "--format=csv,noheader,nounits" -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output=(Get-Content -Raw -Path $stdout -ErrorAction SilentlyContinue).Trim()
        if($process.ExitCode -ne 0 -or -not $output){$detail=(Get-Content -Raw -Path $stderr -ErrorAction SilentlyContinue).Trim();throw "nvidia-smi failed with exit code $($process.ExitCode): $detail"}
        return $output
    } finally { Remove-Item -Force -ErrorAction SilentlyContinue $stdout,$stderr }
}
function Refresh-Path { $machine=[Environment]::GetEnvironmentVariable("Path","Machine");$user=[Environment]::GetEnvironmentVariable("Path","User");$env:Path="$machine;$user;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$BinDir" }
function Require-Command([string]$Name,[string]$Help){if(-not(Get-Command $Name -ErrorAction SilentlyContinue)){throw "$Name was not found. $Help"}}
function Download-File([string]$Url,[string]$Destination){
    $partial="$Destination.part";New-Item -ItemType Directory -Force -Path (Split-Path $Destination)|Out-Null
    Write-Host "Downloading: $Url";Write-Host "To:          $Destination"
    $curlArgs=@("-L","--fail","--retry","8","--retry-all-errors","--retry-delay","2","-o",$partial,$Url);if(Test-Path -LiteralPath $partial){$curlArgs=@("-C","-")+$curlArgs}
    $curlStdout=[IO.Path]::GetTempFileName();$curlStderr=[IO.Path]::GetTempFileName()
    try{$curlPath=(Get-Command "curl.exe" -ErrorAction Stop).Source;$curlProcess=Start-Process -FilePath $curlPath -ArgumentList $curlArgs -Wait -PassThru -RedirectStandardOutput $curlStdout -RedirectStandardError $curlStderr;if($curlProcess.ExitCode -ne 0){$detail=(Get-Content -Raw -Path $curlStderr -ErrorAction SilentlyContinue).Trim();throw "curl failed with exit code $($curlProcess.ExitCode): $detail"}}finally{Remove-Item -Force -ErrorAction SilentlyContinue $curlStdout,$curlStderr}
    if(-not(Test-Path -LiteralPath $partial)){throw "curl completed without creating the partial download: $partial"};Move-Item -Force $partial $Destination
}
function Test-Gguf([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $stream=[IO.File]::OpenRead($Path)
    try { $bytes=New-Object byte[] 4; return $stream.Read($bytes,0,4)-eq 4 -and [Text.Encoding]::ASCII.GetString($bytes)-eq "GGUF" }
    finally { $stream.Dispose() }
}
function Test-CanonicalModel {
    if (-not (Test-Gguf $ModelPath) -or -not (Test-Path -LiteralPath $ModelManifestPath)) { return $false }
    try {
        $manifest=Get-Content -Raw -LiteralPath $ModelManifestPath|ConvertFrom-Json
        $bytes=(Get-Item -LiteralPath $ModelPath).Length
        if($bytes -lt [int64]$ModelLock.canonical_model.target_min_bytes -or $bytes -gt [int64]$ModelLock.canonical_model.target_max_bytes){return $false}
        $sha=(Get-FileHash -Algorithm SHA256 -LiteralPath $ModelPath).Hash.ToLowerInvariant()
        return $manifest.status -eq "CANONICAL_FIXED" -and $manifest.model_file -eq $ModelFile -and $manifest.model_sha256 -eq $sha -and $manifest.parent_revision -eq $ModelLock.uncensored_parent.revision
    } catch { return $false }
}
function Test-Draft {
    if (-not (Test-Gguf $DraftPath)) { return $false }
    if ((Get-Item -LiteralPath $DraftPath).Length -lt [int64]$ModelLock.mtp_draft.minimum_bytes) { return $false }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $DraftPath).Hash.ToLowerInvariant() -eq $DraftSha256.ToLowerInvariant()
}

if($env:OS -ne "Windows_NT"){throw "This runtime is for Windows."}
New-Item -ItemType Directory -Force -Path $RuntimeDir,$LauncherDir,$BinDir,$LlamaDir,$ModelDir,$DownloadDir,$LogDir|Out-Null
Write-Step "Checking NVIDIA GPU";Require-Command "nvidia-smi.exe" "Install or update the NVIDIA driver first.";$gpuInfo=Invoke-NvidiaSmi "name,memory.total";Write-Host $gpuInfo
Write-Step "Checking curl / Node / Python / Git";Require-Command "curl.exe" "Windows 10/11 normally includes curl.exe.";Require-Command "node.exe" "Install Node.js LTS.";Require-Command "python.exe" "Install Python 3.";Require-Command "git.exe" "Install Git for Windows."
Write-Step "Installing OpenCode if needed";Refresh-Path
if(-not(Get-Command "opencode" -ErrorAction SilentlyContinue)){
    if(-not(Get-Command "npm.cmd" -ErrorAction SilentlyContinue)){$winget=Get-Command "winget.exe" -ErrorAction SilentlyContinue;if(-not $winget){throw "Neither npm nor winget is available. Install Node.js LTS and run setup again."};& winget.exe install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements --silent;if($LASTEXITCODE -ne 0){throw "Node.js installation failed with exit code $LASTEXITCODE"};Refresh-Path}
    Require-Command "npm.cmd" "Node.js/npm is not visible in PATH.";& npm.cmd install -g opencode-ai;if($LASTEXITCODE -ne 0){throw "OpenCode installation failed with exit code $LASTEXITCODE"};Refresh-Path
}
Require-Command "opencode" "OpenCode was not found after installation."

Write-Step "Installing llama.cpp Windows CUDA build"
$ServerExe=Join-Path $LlamaDir "llama-server.exe"
$QuantizeExe=Join-Path $LlamaDir "llama-quantize.exe"
if($Force -or $ForceLlama -or -not(Test-Path $ServerExe) -or -not(Test-Path $QuantizeExe)){
    $releases=Invoke-RestMethod -Headers @{"User-Agent"="BLACK-Code-Setup"} -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=20";$picked=$null
    foreach($release in $releases){$main=$release.assets|Where-Object{$_.name -match '^llama-b.*-bin-win-cuda-12\.4-x64\.zip$'}|Select-Object -First 1;$cudart=$release.assets|Where-Object{$_.name -eq 'cudart-llama-bin-win-cuda-12.4-x64.zip'}|Select-Object -First 1;if($main -and $cudart){$picked=[PSCustomObject]@{tag=$release.tag_name;main=$main;cudart=$cudart};break}}
    if(-not $picked){throw "Could not find a recent llama.cpp Windows CUDA 12.4 release."};Write-Host "llama.cpp release: $($picked.tag)"
    $mainZip=Join-Path $DownloadDir $picked.main.name;$cudaZip=Join-Path $DownloadDir $picked.cudart.name
    if($Force -or $ForceLlama -or -not(Test-Path $mainZip)){Download-File $picked.main.browser_download_url $mainZip};if($Force -or $ForceLlama -or -not(Test-Path $cudaZip)){Download-File $picked.cudart.browser_download_url $cudaZip}
    $stage=Join-Path $RuntimeDir "llama-stage";if(Test-Path $stage){Remove-Item -Recurse -Force $stage};New-Item -ItemType Directory -Force -Path (Join-Path $stage "main"),(Join-Path $stage "cuda")|Out-Null
    Expand-Archive -Force -Path $mainZip -DestinationPath (Join-Path $stage "main");Expand-Archive -Force -Path $cudaZip -DestinationPath (Join-Path $stage "cuda")
    $foundServer=Get-ChildItem (Join-Path $stage "main") -Recurse -Filter "llama-server.exe"|Select-Object -First 1;if(-not $foundServer){throw "llama-server.exe was not found in the downloaded archive."}
    Get-ChildItem $LlamaDir -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force;Copy-Item -Path (Join-Path $foundServer.Directory.FullName "*") -Destination $LlamaDir -Recurse -Force;Get-ChildItem (Join-Path $stage "cuda") -Recurse -File|ForEach-Object{Copy-Item -Force $_.FullName (Join-Path $LlamaDir $_.Name)};Remove-Item -Recurse -Force $stage
}
if(-not(Test-Path $ServerExe) -or -not(Test-Path $QuantizeExe)){throw "llama.cpp installation did not include server + quantizer."};& $ServerExe --version;if($LASTEXITCODE -ne 0){throw "llama-server.exe exists but failed to run."}

$hfDownloader=Join-Path $PSScriptRoot "hf-parallel-download.ps1"
if(-not(Test-Path -LiteralPath $hfDownloader)){throw "hf-parallel-download.ps1 is missing from BLACK Code runtime."}

Write-Step "Building fixed BLACK 7.27 GB uncensored model"
if($Force -or -not(Test-CanonicalModel)){
    $builder=Join-Path $PSScriptRoot "build-model-7.27.ps1"
    if(-not(Test-Path -LiteralPath $builder)){throw "build-model-7.27.ps1 is missing."}
    if($Force){& $builder -ModelDir $ModelDir -LlamaBinDir $LlamaDir -HfDownloadWorkers $HfDownloadWorkers -ForceRebuild}
    else{& $builder -ModelDir $ModelDir -LlamaBinDir $LlamaDir -HfDownloadWorkers $HfDownloadWorkers}
    if($LASTEXITCODE -ne 0){throw "BLACK 7.27 model build failed with exit code $LASTEXITCODE"}
}
if(-not(Test-CanonicalModel)){throw "BLACK 7.27 canonical model failed manifest/hash/size verification."}
$modelManifest=Get-Content -Raw -LiteralPath $ModelManifestPath|ConvertFrom-Json
Write-Host "Canonical model: $ModelFile" -ForegroundColor Green
Write-Host "Size: $($modelManifest.model_size_decimal_gb) GB / SHA256: $($modelManifest.model_sha256)"

Write-Step "Downloading fixed Uncensored MTP draft from Hugging Face"
if($Force -or -not(Test-Draft)){
    if(Test-Path -LiteralPath $DraftPath){Move-Item -Force $DraftPath "$DraftPath.invalid"}
    & $hfDownloader -Url $DraftUrl -Destination $DraftPath -Workers $HfDownloadWorkers
    if($LASTEXITCODE -ne 0){throw "MTP draft download failed with exit code $LASTEXITCODE"}
}
if(-not(Test-Draft)){throw "MTP draft verification failed. Expected SHA256 $DraftSha256"}
Write-Host "MTP draft HASH VERIFIED: $DraftFile" -ForegroundColor Green

foreach($legacy in $LegacyModelPaths){if(Test-Path -LiteralPath $legacy){Remove-Item -Force $legacy;Write-Host "Removed superseded model: $legacy"}}

Write-Step "Installing BLACK Code launcher"
$launcherFiles=@("black-code.ps1","setup.ps1","doctor.ps1","execution-fabric.ps1","repo-index.ps1","rule-bridge.ps1","verification-gate.ps1","hf-parallel-download.ps1","build-model-7.27.ps1","extract-quant-map.mjs","model-7.27.lock.json","black-code-execution.md","analyze-bottleneck.ps1","opencode-telemetry.js","opencode-governor.js","verify.ps1")
foreach($name in $launcherFiles){$source=Join-Path $PSScriptRoot $name;if(-not(Test-Path $source)){throw "Required runtime source missing: $source"};Copy-Item -Force $source (Join-Path $LauncherDir $name)}

$globalPluginDir=Join-Path $env:USERPROFILE ".config\opencode\plugins"
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $globalPluginDir "black-code-telemetry.js"),(Join-Path $globalPluginDir "black-code-governor.js")

$Shim=Join-Path $BinDir "black-code.cmd";$InstalledLauncher=Join-Path $LauncherDir "black-code.ps1";$shimText="@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstalledLauncher`" %*`r`n";Set-Content -Encoding ASCII -Path $Shim -Value $shimText
$VerifyShim=Join-Path $BinDir "black-code-verify.cmd";$InstalledVerify=Join-Path $LauncherDir "verification-gate.ps1";$verifyShimText="@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstalledVerify`" %*`r`n";Set-Content -Encoding ASCII -Path $VerifyShim -Value $verifyShimText
$userPath=[Environment]::GetEnvironmentVariable("Path","User");if([string]::IsNullOrWhiteSpace($userPath)){$userPath=""};$parts=$userPath.Split(';')|Where-Object{-not[string]::IsNullOrWhiteSpace($_)};if($parts -notcontains $BinDir){[Environment]::SetEnvironmentVariable("Path",(($parts+$BinDir)-join ';'),"User")};Refresh-Path

$state=[ordered]@{
    installed_at=(Get-Date).ToString("o")
    canonical_runtime="opencode-llama-governed-v4-black-7.27"
    model=$ModelFile
    model_sha256=$modelManifest.model_sha256
    model_path=$ModelPath
    model_size_bytes=$modelManifest.model_bytes
    model_size_decimal_gb=$modelManifest.model_size_decimal_gb
    model_role="canonical-fixed"
    model_parent_revision=$modelManifest.parent_revision
    model_manifest=$ModelManifestPath
    mtp_draft=$DraftFile
    mtp_draft_sha256=$DraftSha256
    mtp_draft_path=$DraftPath
    llama_server=$ServerExe
    gpu=($gpuInfo -join "; ")
    execution_fabric="black-execution-fabric-governed-v3"
    repo_index="persistent-delta-v1"
    rule_bridge="claude-black-compatible-v1"
    completion_governor="hash-bound-v2"
    final_verifier="governed-final-v2"
    bottleneck_analyzer="observation-only-v1"
    quantization="BLACK-UD-IQ2_XXS-exact-reference-map"
    speculative="external-draft-mtp"
    mtp_draft_max=2
    local_parallel_slots=1
    vision=$false
    ngram_mod=$false
    forced_cache_reuse=$false
    hf_parallel_workers=$HfDownloadWorkers
    default_context="auto-8192-12288-16384"
}
$state|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $RuntimeDir "state.json")
Write-Host "";Write-Host "BLACK CODE 7.27 LOCAL RUNTIME VERIFIED" -ForegroundColor Green;Write-Host "Open a new terminal in any code repository and run:";Write-Host "";Write-Host "    black-code" -ForegroundColor Yellow
