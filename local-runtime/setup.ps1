param(
    [switch]$Force,
    [switch]$ForceLlama,
    [string]$ModelWorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [switch]$PurgeModelDownloadCache,
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
$RuntimeLockPath = Join-Path $PSScriptRoot "runtime.lock.json"
if (-not (Test-Path -LiteralPath $ModelLockPath)) { throw "model-7.27.lock.json is missing." }
if (-not (Test-Path -LiteralPath $RuntimeLockPath)) { throw "runtime.lock.json is missing." }
$ModelLock = Get-Content -Raw -LiteralPath $ModelLockPath | ConvertFrom-Json
$RuntimeLock = Get-Content -Raw -LiteralPath $RuntimeLockPath | ConvertFrom-Json
$ModelFile = [string]$ModelLock.canonical_model.file
$ModelPath = Join-Path $ModelDir $ModelFile
$ModelManifestPath = Join-Path $ModelDir "model-7.27.local.json"
$DraftFile = [string]$ModelLock.mtp_draft.file
$DraftPath = Join-Path $ModelDir $DraftFile
$DraftUrl = "https://huggingface.co/" + [string]$ModelLock.mtp_draft.repo + "/resolve/" + [string]$ModelLock.mtp_draft.revision + "/" + $DraftFile + "?download=true"
$DraftSha256 = [string]$ModelLock.mtp_draft.sha256
$OpenCodeVersion = [string]$RuntimeLock.opencode.version
$LlamaTag = [string]$RuntimeLock.llama_cpp.binary_tag
$LlamaCommit = [string]$RuntimeLock.llama_cpp.target_commit
$LlamaMain = $RuntimeLock.llama_cpp.windows_x64_main
$LlamaCuda = $RuntimeLock.llama_cpp.windows_x64_cudart
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
function Test-FileSha([string]$Path,[string]$Expected) {
    if(-not(Test-Path -LiteralPath $Path)){return $false}
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() -eq $Expected.ToLowerInvariant()
}
function Ensure-PinnedDownload([string]$Url,[string]$Destination,[string]$ExpectedSha) {
    if(Test-FileSha $Destination $ExpectedSha){return}
    if(Test-Path -LiteralPath $Destination){Move-Item -Force $Destination "$Destination.invalid"}
    Download-File $Url $Destination
    if(-not(Test-FileSha $Destination $ExpectedSha)){throw "Pinned download SHA mismatch: $Destination"}
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
        $ranges=@($manifest.quant_map_reference_range_evidence)
        if($ranges.Count -lt 1){return $false}
        foreach($range in $ranges){
            if([int64]$range.received_bytes -le 0 -or [int64]$range.remote_total_bytes -le [int64]$range.received_bytes -or ([string]$range.sha256) -notmatch '^[0-9a-f]{64}$' -or ([string]$range.content_range) -notmatch '^bytes 0-[0-9]+/[0-9]+$'){return $false}
        }
        return $manifest.schema_version -eq "1.1" -and
            $manifest.status -eq "CANONICAL_FIXED" -and
            $manifest.model_file -eq $ModelFile -and
            [int64]$manifest.model_bytes -eq $bytes -and
            ([string]$manifest.model_sha256).ToLowerInvariant() -eq $sha -and
            $manifest.no_mtp -eq $true -and $manifest.vision -eq $false -and
            $manifest.parent_repo -eq $ModelLock.uncensored_parent.repo -and
            $manifest.parent_revision -eq $ModelLock.uncensored_parent.revision -and
            $manifest.parent_snapshot_verified_complete -eq $true -and
            $manifest.quant_map_reference_repo -eq $ModelLock.quant_map_reference.repo -and
            $manifest.quant_map_reference_revision -eq $ModelLock.quant_map_reference.revision -and
            ([string]$manifest.quant_map_reference_expected_full_sha256).ToLowerInvariant() -eq ([string]$ModelLock.quant_map_reference.sha256).ToLowerInvariant() -and
            $manifest.quant_map_reference_full_sha256_measured -eq $false -and $manifest.quant_map_reference_full_downloaded -eq $false -and
            ([string]$manifest.imatrix_sha256).ToLowerInvariant() -eq ([string]$ModelLock.imatrix.sha256).ToLowerInvariant() -and
            [int64]$manifest.tensor_map_entries -ge 100 -and ([string]$manifest.tensor_map_sha256) -match '^[0-9a-f]{64}$' -and
            ([string]$manifest.reference_tensor_inventory_sha256) -match '^[0-9a-f]{64}$' -and
            [int64]$manifest.local_f16_bytes -gt 0 -and ([string]$manifest.local_f16_sha256) -match '^[0-9a-f]{64}$' -and
            $manifest.local_f16_provenance_verified -eq $true -and [int64]$manifest.local_f16_tensor_count -eq [int64]$manifest.tensor_map_entries -and
            ([string]$manifest.local_f16_tensor_inventory_sha256) -match '^[0-9a-f]{64}$' -and
            $manifest.local_f16_tensor_inventory_sha256 -eq $manifest.reference_tensor_inventory_sha256 -and $manifest.local_f16_names_match_reference -eq $true -and
            $manifest.llama_conversion_revision -eq $ModelLock.llama_cpp_conversion_source.revision -and
            $manifest.quantization -eq "BLACK-UD-IQ2_XXS exact-reference-tensor-map"
    } catch { return $false }
}
function Test-Draft {
    if (-not (Test-Gguf $DraftPath)) { return $false }
    if ((Get-Item -LiteralPath $DraftPath).Length -lt [int64]$ModelLock.mtp_draft.minimum_bytes) { return $false }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $DraftPath).Hash.ToLowerInvariant() -eq $DraftSha256.ToLowerInvariant()
}
function Get-OpenCodeVersion {
    $oc=Get-Command "opencode" -ErrorAction SilentlyContinue
    if(-not $oc){return $null}
    try{return ((& $oc.Source --version 2>$null | Select-Object -First 1).ToString().Trim())}catch{return $null}
}
function Test-OpenCodePackagePinned {
    try {
        $root=((& npm.cmd root -g 2>$null)|Select-Object -First 1).ToString().Trim()
        if($LASTEXITCODE -ne 0 -or -not $root){return $false}
        $packagePath=Join-Path $root (([string]$RuntimeLock.opencode.npm_package)+"\package.json")
        if(-not(Test-Path -LiteralPath $packagePath)){return $false}
        $package=Get-Content -Raw -LiteralPath $packagePath|ConvertFrom-Json
        return $package.name -eq [string]$RuntimeLock.opencode.npm_package -and $package.version -eq $OpenCodeVersion
    } catch { return $false }
}
function Test-LlamaPinned([string]$ServerExe,[string]$QuantizeExe) {
    if(-not(Test-Path -LiteralPath $ServerExe) -or -not(Test-Path -LiteralPath $QuantizeExe)){return $false}
    try {
        $text=((& $ServerExe --version 2>&1)|Out-String)
        $commitPrefix=$LlamaCommit.Substring(0,8)
        $buildMatches = $text -match [regex]::Escape($LlamaTag) -or $text -match '(?i)build\s+10809'
        return $buildMatches -and $text -match [regex]::Escape($commitPrefix)
    } catch { return $false }
}

if($env:OS -ne "Windows_NT"){throw "This runtime is for Windows."}
New-Item -ItemType Directory -Force -Path $RuntimeDir,$LauncherDir,$BinDir,$LlamaDir,$ModelDir,$DownloadDir,$LogDir|Out-Null
Write-Step "Checking NVIDIA GPU";Require-Command "nvidia-smi.exe" "Install or update the NVIDIA driver first.";$gpuInfo=Invoke-NvidiaSmi "name,memory.total";Write-Host $gpuInfo
Write-Step "Checking curl / Node / Python / Git";Require-Command "curl.exe" "Windows 10/11 normally includes curl.exe.";Require-Command "node.exe" "Install Node.js LTS.";Require-Command "python.exe" "Install Python 3.";Require-Command "git.exe" "Install Git for Windows."

Write-Step "Enforcing pinned OpenCode $OpenCodeVersion";Refresh-Path
if(-not(Get-Command "npm.cmd" -ErrorAction SilentlyContinue)){
    $winget=Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if(-not $winget){throw "Neither npm nor winget is available. Install Node.js LTS and run setup again."}
    & winget.exe install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements --silent
    if($LASTEXITCODE -ne 0){throw "Node.js installation failed with exit code $LASTEXITCODE"}
    Refresh-Path
}
Require-Command "npm.cmd" "Node.js/npm is not visible in PATH."
if((Get-OpenCodeVersion) -ne $OpenCodeVersion){
    & npm.cmd install -g ("opencode-ai@"+$OpenCodeVersion)
    if($LASTEXITCODE -ne 0){throw "Pinned OpenCode installation failed with exit code $LASTEXITCODE"}
    Refresh-Path
}
Require-Command "opencode" "OpenCode was not found after installation."
$actualOpenCodeVersion=Get-OpenCodeVersion
if($actualOpenCodeVersion -ne $OpenCodeVersion -or -not(Test-OpenCodePackagePinned)){throw "OpenCode package/version mismatch. Expected $($RuntimeLock.opencode.npm_package)@$OpenCodeVersion, got CLI $actualOpenCodeVersion"}
Write-Host "OpenCode PIN VERIFIED: $actualOpenCodeVersion" -ForegroundColor Green

Write-Step "Enforcing pinned llama.cpp $LlamaTag / CUDA $($RuntimeLock.llama_cpp.cuda)"
$ServerExe=Join-Path $LlamaDir "llama-server.exe"
$QuantizeExe=Join-Path $LlamaDir "llama-quantize.exe"
if($Force -or $ForceLlama -or -not(Test-LlamaPinned $ServerExe $QuantizeExe)){
    $mainZip=Join-Path $DownloadDir ([string]$LlamaMain.file)
    $cudaZip=Join-Path $DownloadDir ([string]$LlamaCuda.file)
    if($Force -or $ForceLlama){Remove-Item -Force -ErrorAction SilentlyContinue $mainZip,$cudaZip}
    Ensure-PinnedDownload ([string]$LlamaMain.url) $mainZip ([string]$LlamaMain.sha256)
    Ensure-PinnedDownload ([string]$LlamaCuda.url) $cudaZip ([string]$LlamaCuda.sha256)
    $stage=Join-Path $RuntimeDir "llama-stage";if(Test-Path $stage){Remove-Item -Recurse -Force $stage};New-Item -ItemType Directory -Force -Path (Join-Path $stage "main"),(Join-Path $stage "cuda")|Out-Null
    Expand-Archive -Force -Path $mainZip -DestinationPath (Join-Path $stage "main");Expand-Archive -Force -Path $cudaZip -DestinationPath (Join-Path $stage "cuda")
    $foundServer=Get-ChildItem (Join-Path $stage "main") -Recurse -Filter "llama-server.exe"|Select-Object -First 1;if(-not $foundServer){throw "llama-server.exe was not found in the pinned archive."}
    Get-ChildItem $LlamaDir -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force
    Copy-Item -Path (Join-Path $foundServer.Directory.FullName "*") -Destination $LlamaDir -Recurse -Force
    Get-ChildItem (Join-Path $stage "cuda") -Recurse -File|ForEach-Object{Copy-Item -Force $_.FullName (Join-Path $LlamaDir $_.Name)}
    Remove-Item -Recurse -Force $stage
}
if(-not(Test-LlamaPinned $ServerExe $QuantizeExe)){throw "llama.cpp install does not match runtime.lock.json ($LlamaTag / $LlamaCommit)."}
$llamaVersionText=((& $ServerExe --version 2>&1)|Out-String).Trim()
Write-Host "llama.cpp PIN VERIFIED: $LlamaTag" -ForegroundColor Green

$hfDownloader=Join-Path $PSScriptRoot "hf-parallel-download.ps1"
if(-not(Test-Path -LiteralPath $hfDownloader)){throw "hf-parallel-download.ps1 is missing from BLACK Code runtime."}

Write-Step "Building fixed BLACK 7.27 GB uncensored model"
if($Force -or -not(Test-CanonicalModel)){
    $builder=Join-Path $PSScriptRoot "build-model-7.27.ps1"
    if(-not(Test-Path -LiteralPath $builder)){throw "build-model-7.27.ps1 is missing."}
    if($Force -and $PurgeModelDownloadCache){
        & $builder -ModelDir $ModelDir -LlamaBinDir $LlamaDir -WorkDir $ModelWorkDir -HfDownloadWorkers $HfDownloadWorkers -ForceRebuild -PurgeDownloadCache
    } elseif($Force) {
        & $builder -ModelDir $ModelDir -LlamaBinDir $LlamaDir -WorkDir $ModelWorkDir -HfDownloadWorkers $HfDownloadWorkers -ForceRebuild
    } elseif($PurgeModelDownloadCache) {
        & $builder -ModelDir $ModelDir -LlamaBinDir $LlamaDir -WorkDir $ModelWorkDir -HfDownloadWorkers $HfDownloadWorkers -PurgeDownloadCache
    } else {
        & $builder -ModelDir $ModelDir -LlamaBinDir $LlamaDir -WorkDir $ModelWorkDir -HfDownloadWorkers $HfDownloadWorkers
    }
    if($LASTEXITCODE -ne 0){throw "BLACK 7.27 model build failed with exit code $LASTEXITCODE"}
}
if(-not(Test-CanonicalModel)){throw "BLACK 7.27 canonical model failed manifest/hash/size verification."}
$modelManifest=Get-Content -Raw -LiteralPath $ModelManifestPath|ConvertFrom-Json
Write-Host "Canonical model: $ModelFile" -ForegroundColor Green
Write-Host "Size: $($modelManifest.model_size_decimal_gb) GB / SHA256: $($modelManifest.model_sha256)"

Write-Step "Downloading fixed Uncensored MTP draft from Hugging Face"
if(-not(Test-Draft)){
    if(Test-Path -LiteralPath $DraftPath){Move-Item -Force $DraftPath "$DraftPath.invalid"}
    & $hfDownloader -Url $DraftUrl -Destination $DraftPath -Workers $HfDownloadWorkers
    if($LASTEXITCODE -ne 0){throw "MTP draft download failed with exit code $LASTEXITCODE"}
}
if(-not(Test-Draft)){throw "MTP draft verification failed. Expected SHA256 $DraftSha256"}
Write-Host "MTP draft HASH VERIFIED: $DraftFile" -ForegroundColor Green

foreach($legacy in $LegacyModelPaths){if(Test-Path -LiteralPath $legacy){Remove-Item -Force $legacy;Write-Host "Removed superseded model: $legacy"}}

Write-Step "Installing BLACK Code launcher"
$launcherFiles=@("black-code.ps1","setup.ps1","doctor.ps1","execution-fabric.ps1","repo-index.ps1","rule-bridge.ps1","verification-gate.ps1","hf-parallel-download.ps1","build-model-7.27.ps1","extract-quant-map.mjs","model-7.27.lock.json","runtime.lock.json","black-code-execution.md","analyze-bottleneck.ps1","opencode-telemetry.js","opencode-governor.js","verify.ps1")
foreach($name in $launcherFiles){$source=Join-Path $PSScriptRoot $name;if(-not(Test-Path $source)){throw "Required runtime source missing: $source"};Copy-Item -Force $source (Join-Path $LauncherDir $name)}

$globalPluginDir=Join-Path $env:USERPROFILE ".config\opencode\plugins"
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $globalPluginDir "black-code-telemetry.js"),(Join-Path $globalPluginDir "black-code-governor.js")

$Shim=Join-Path $BinDir "black-code.cmd";$InstalledLauncher=Join-Path $LauncherDir "black-code.ps1";$shimText="@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstalledLauncher`" %*`r`n";Set-Content -Encoding ASCII -Path $Shim -Value $shimText
$VerifyShim=Join-Path $BinDir "black-code-verify.cmd";$InstalledVerify=Join-Path $LauncherDir "verification-gate.ps1";$verifyShimText="@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstalledVerify`" %*`r`n";Set-Content -Encoding ASCII -Path $VerifyShim -Value $verifyShimText
$userPath=[Environment]::GetEnvironmentVariable("Path","User");if([string]::IsNullOrWhiteSpace($userPath)){$userPath=""};$parts=$userPath.Split(';')|Where-Object{-not[string]::IsNullOrWhiteSpace($_)};if($parts -notcontains $BinDir){[Environment]::SetEnvironmentVariable("Path",(($parts+$BinDir)-join ';'),"User")};Refresh-Path

$state=[ordered]@{
    installed_at=(Get-Date).ToString("o")
    canonical_runtime="opencode-llama-governed-v5-black-7.27"
    runtime_lock="runtime.lock.json"
    opencode_version=$OpenCodeVersion
    llama_release=[string]$RuntimeLock.llama_cpp.semantic_release
    llama_binary_tag=$LlamaTag
    llama_commit=$LlamaCommit
    llama_version=$llamaVersionText
    model=$ModelFile
    model_sha256=$modelManifest.model_sha256
    model_path=$ModelPath
    model_size_bytes=$modelManifest.model_bytes
    model_size_decimal_gb=$modelManifest.model_size_decimal_gb
    model_role="canonical-fixed"
    model_parent_revision=$modelManifest.parent_revision
    model_manifest=$ModelManifestPath
    model_work_dir=$ModelWorkDir
    mtp_draft=$DraftFile
    mtp_draft_sha256=$DraftSha256
    mtp_draft_path=$DraftPath
    llama_server=$ServerExe
    gpu=($gpuInfo -join "; ")
    execution_fabric="black-execution-fabric-governed-v3"
    repo_index="persistent-delta-v2-untracked"
    rule_bridge="claude-black-compatible-v1"
    completion_governor="workspace-runtime-bound-v3"
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
