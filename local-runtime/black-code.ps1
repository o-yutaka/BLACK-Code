param(
    [ValidateSet('FAST','CODE','DEEP')]
    [string]$Tier = '',
    [ValidateRange(8192, 65536)]
    [int]$Context = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0

$InstallBase = Join-Path $env:LOCALAPPDATA "BLACK-Code"
$RuntimeDir = Join-Path $InstallBase "runtime"
$LauncherDir = Join-Path $InstallBase "launcher"
$LlamaDir = Join-Path $RuntimeDir "llama"
$ModelDir = Join-Path $RuntimeDir "models"
$LogDir = Join-Path $RuntimeDir "logs"
$BinDir = Join-Path $InstallBase "bin"
$FabricEvidenceDir = Join-Path $RuntimeDir "execution-fabric"
$RepoIndexRoot = Join-Path $RuntimeDir "repo-index"
$BottleneckDir = Join-Path $RuntimeDir "bottlenecks"
$GovernorDir = Join-Path $RuntimeDir "governor"

$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelFile = "Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf"
$ModelPath = Join-Path $ModelDir $ModelFile
$ModelManifestPath = Join-Path $ModelDir "model-7.27.local.json"
$DraftFile = "Qwen3.8-27B-Uncensored-draft-Q4_0.gguf"
$DraftPath = Join-Path $ModelDir $DraftFile
$ModelAlias = "qwen3.8-27b-uncensored-black-7.27"
$ProviderId = "black-local"
$ModelId = "$ProviderId/$ModelAlias"

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$BinDir"
}
function Invoke-NvidiaSmi([string]$Query) {
    $stdout = [IO.Path]::GetTempFileName(); $stderr = [IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath (Get-Command "nvidia-smi.exe").Source -ArgumentList "--query-gpu=$Query", "--format=csv,noheader,nounits" -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output = (Get-Content -Raw -Path $stdout -ErrorAction SilentlyContinue).Trim()
        if ($process.ExitCode -ne 0 -or -not $output) { $detail = (Get-Content -Raw -Path $stderr -ErrorAction SilentlyContinue).Trim(); throw "nvidia-smi failed with exit code $($process.ExitCode): $detail" }
        return $output
    }
    finally { Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr }
}
function Find-FreePort([int]$Start, [int]$End) {
    for ($p = $Start; $p -le $End; $p++) {
        try { $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $p); $listener.Start(); $listener.Stop(); return $p } catch {}
    }
    throw "No free local port found in range $Start-$End."
}
function Resolve-SetupScript {
    $near = Join-Path $PSScriptRoot "setup.ps1"; if (Test-Path $near) { return $near }
    $installed = Join-Path $LauncherDir "setup.ps1"; if (Test-Path $installed) { return $installed }
    throw "setup.ps1 was not found. Re-clone BLACK-Code or restore the local launcher."
}
function Resolve-RuntimeFile([string]$Name) {
    $near = Join-Path $PSScriptRoot $Name; if (Test-Path $near) { return (Resolve-Path -LiteralPath $near).Path }
    $installed = Join-Path $LauncherDir $Name; if (Test-Path $installed) { return (Resolve-Path -LiteralPath $installed).Path }
    throw "$Name was not found. Run BLACK Code setup from the latest repository checkout."
}
function Convert-ToFileUri([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path.Replace('\', '/')
    return "file:///$resolved"
}
function Ensure-Installed {
    Refresh-Path
    $opencode = Get-Command "opencode" -ErrorAction SilentlyContinue
    if (-not (Test-Path $ServerExe) -or -not (Test-Path $ModelPath) -or -not (Test-Path $ModelManifestPath) -or -not (Test-Path $DraftPath) -or -not $opencode) {
        Write-Host "Local runtime is incomplete. Running BLACK Code setup..." -ForegroundColor Yellow
        & (Resolve-SetupScript)
        if ($LASTEXITCODE -ne 0) { throw "BLACK Code setup failed." }
        Refresh-Path
    }
}

Ensure-Installed
New-Item -ItemType Directory -Force -Path $LogDir, $FabricEvidenceDir, $RepoIndexRoot, $BottleneckDir, $GovernorDir | Out-Null
. (Resolve-RuntimeFile "execution-fabric.ps1")
. (Resolve-RuntimeFile "repo-index.ps1")

$modelLock = Get-Content -Raw -LiteralPath (Resolve-RuntimeFile "model-7.27.lock.json") | ConvertFrom-Json
$runtimeLock = Get-Content -Raw -LiteralPath (Resolve-RuntimeFile "runtime.lock.json") | ConvertFrom-Json
if ($ModelFile -ne [string]$modelLock.canonical_model.file -or $DraftFile -ne [string]$modelLock.mtp_draft.file) { throw "Runtime model names do not match the canonical lock files." }
$modelManifest = Get-Content -Raw -LiteralPath $ModelManifestPath | ConvertFrom-Json
$actualModelBytes = (Get-Item -LiteralPath $ModelPath).Length
$actualModelSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $ModelPath).Hash.ToLowerInvariant()
$rangeEvidence = @($modelManifest.quant_map_reference_range_evidence)
$rangeEvidenceValid = $rangeEvidence.Count -ge 1
foreach($range in $rangeEvidence){
    if([int64]$range.received_bytes -le 0 -or [int64]$range.remote_total_bytes -le [int64]$range.received_bytes -or ([string]$range.sha256) -notmatch '^[0-9a-f]{64}$' -or ([string]$range.content_range) -notmatch '^bytes 0-[0-9]+/[0-9]+$'){$rangeEvidenceValid=$false}
}
if ($modelManifest.schema_version -ne "1.1" -or $modelManifest.status -ne "CANONICAL_FIXED" -or $modelManifest.model_file -ne $ModelFile -or
    [int64]$modelManifest.model_bytes -ne $actualModelBytes -or ([string]$modelManifest.model_sha256).ToLowerInvariant() -ne $actualModelSha -or
    $modelManifest.no_mtp -ne $true -or $modelManifest.vision -ne $false -or
    $modelManifest.parent_repo -ne $modelLock.uncensored_parent.repo -or $modelManifest.parent_revision -ne $modelLock.uncensored_parent.revision -or
    $modelManifest.parent_snapshot_verified_complete -ne $true -or
    $modelManifest.quant_map_reference_repo -ne $modelLock.quant_map_reference.repo -or $modelManifest.quant_map_reference_revision -ne $modelLock.quant_map_reference.revision -or
    ([string]$modelManifest.quant_map_reference_expected_full_sha256).ToLowerInvariant() -ne ([string]$modelLock.quant_map_reference.sha256).ToLowerInvariant() -or
    $modelManifest.quant_map_reference_full_sha256_measured -ne $false -or $modelManifest.quant_map_reference_full_downloaded -ne $false -or -not $rangeEvidenceValid -or
    ([string]$modelManifest.imatrix_sha256).ToLowerInvariant() -ne ([string]$modelLock.imatrix.sha256).ToLowerInvariant() -or
    [int64]$modelManifest.tensor_map_entries -lt 100 -or ([string]$modelManifest.tensor_map_sha256) -notmatch '^[0-9a-f]{64}$' -or
    ([string]$modelManifest.reference_tensor_inventory_sha256) -notmatch '^[0-9a-f]{64}$' -or
    [int64]$modelManifest.local_f16_bytes -le 0 -or ([string]$modelManifest.local_f16_sha256) -notmatch '^[0-9a-f]{64}$' -or $modelManifest.local_f16_provenance_verified -ne $true -or
    [int64]$modelManifest.local_f16_tensor_count -ne [int64]$modelManifest.tensor_map_entries -or ([string]$modelManifest.local_f16_tensor_inventory_sha256) -notmatch '^[0-9a-f]{64}$' -or
    $modelManifest.local_f16_names_match_reference -ne $true -or
    $modelManifest.llama_conversion_revision -ne $modelLock.llama_cpp_conversion_source.revision -or
    $modelManifest.quantization -ne "BLACK-UD-IQ2_XXS exact-reference-tensor-map") { throw "BLACK 7.27 model artifact/manifest/lock integrity verification failed. Run setup.ps1 again." }
$actualDraftBytes = (Get-Item -LiteralPath $DraftPath).Length
$actualDraftSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $DraftPath).Hash.ToLowerInvariant()
if ($actualDraftBytes -lt [int64]$modelLock.mtp_draft.minimum_bytes -or $actualDraftSha -ne ([string]$modelLock.mtp_draft.sha256).ToLowerInvariant()) { throw "BLACK 7.27 MTP artifact failed its pinned size/SHA verification. Run setup.ps1 again." }
$verOut = [IO.Path]::GetTempFileName(); $verErr = [IO.Path]::GetTempFileName(); $llamaExit = -1
try {
    $verProc = Start-Process -FilePath $ServerExe -ArgumentList "--version" -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $verOut -RedirectStandardError $verErr
    $llamaExit = $verProc.ExitCode
    $llamaText = ((Get-Content -Raw -Path $verOut -ErrorAction SilentlyContinue) + (Get-Content -Raw -Path $verErr -ErrorAction SilentlyContinue))
}
finally { Remove-Item -Force -ErrorAction SilentlyContinue $verOut, $verErr }
$llamaTag = [string]$runtimeLock.llama_cpp.binary_tag
$llamaPrefix = ([string]$runtimeLock.llama_cpp.target_commit).Substring(0,8)
if ($llamaExit -ne 0 -or (($llamaText -notmatch [regex]::Escape($llamaTag)) -and ($llamaText -notmatch '(?i)build\s+10809')) -or $llamaText -notmatch [regex]::Escape($llamaPrefix)) { throw "llama.cpp runtime does not match pinned $llamaTag / $llamaPrefix." }
Refresh-Path
$pinnedOpenCode = [string]$runtimeLock.opencode.version
$openCodeCommand = Get-Command "opencode" -ErrorAction Stop
$actualOpenCode = ((& $openCodeCommand.Source --version 2>$null | Select-Object -First 1).ToString().Trim())
if ($LASTEXITCODE -ne 0 -or $actualOpenCode -ne $pinnedOpenCode) { throw "OpenCode runtime version mismatch. Expected $pinnedOpenCode, got $actualOpenCode." }
$npmRoot = Split-Path -Parent $openCodeCommand.Source
$openCodePackagePath = Join-Path $npmRoot (Join-Path "node_modules" (([string]$runtimeLock.opencode.npm_package)+"\package.json"))
$openCodePackage = Get-Content -Raw -LiteralPath $openCodePackagePath | ConvertFrom-Json
if ($openCodePackage.name -ne [string]$runtimeLock.opencode.npm_package -or $openCodePackage.version -ne $pinnedOpenCode) { throw "OpenCode global package metadata does not match runtime.lock.json." }

$projectRoot = (Get-Location).Path
$repoIndex = Get-BlackCodeRepoIndex -ProjectRoot $projectRoot -IndexRoot $RepoIndexRoot
$trackedFileCount = $repoIndex.index.tracked_file_count
$instructionSource = Resolve-RuntimeFile "black-code-execution.md"
$instructionRuntimePath = Join-Path $RuntimeDir "black-code-execution.md"
$repoContextRuntimePath = Join-Path $RuntimeDir "repo-context.md"
$projectRulesRuntimePath = Join-Path $RuntimeDir "project-rules.md"
Copy-Item -Force $instructionSource $instructionRuntimePath
Copy-Item -Force $repoIndex.context_path $repoContextRuntimePath
& (Resolve-RuntimeFile "rule-bridge.ps1") -ProjectRoot $projectRoot -Destination $projectRulesRuntimePath

$rulesSource = Resolve-RuntimeFile "black-code-rules.md"
$rulesRuntimePath = Join-Path $RuntimeDir "black-code-rules.md"
Copy-Item -Force $rulesSource $rulesRuntimePath
$execContent = Get-Content -Raw -LiteralPath $instructionRuntimePath
if ($execContent -match 'RUNTIME_RULES_PATH') {
    Set-Content -Encoding UTF8 -LiteralPath $instructionRuntimePath -Value ($execContent -replace [regex]::Escape('RUNTIME_RULES_PATH'), $rulesRuntimePath)
}

$gpuLine = ((Invoke-NvidiaSmi "name,memory.total,memory.free") -split "`r?`n")[0]
$gpuParts = $gpuLine -split ',' | ForEach-Object { $_.Trim() }
$gpuName = $gpuParts[0]; $totalVram = [int]$gpuParts[1]; $freeVram = [int]$gpuParts[2]
$ramGiB = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$contextReason = "explicit"

# Prompt Budget Governor trailhead: OpenCode's base prompt + tool schemas +
# injected instructions are reduced per Tier, so the default context stays at a
# common 16K (FAST) instead of needing 32K just to contain the boot prompt.
# A full all-schema first request measured 21,839 tokens on an empty repo.
if ($Tier -eq '') {
    if ($Context -gt 0) {
        if ($Context -le 18432) { $Tier = 'FAST' }
        elseif ($Context -le 28672) { $Tier = 'CODE' }
        else { $Tier = 'DEEP' }
    }
    elseif ($trackedFileCount -le 150) { $Tier = 'FAST' }
    elseif ($trackedFileCount -le 800) { $Tier = 'CODE' }
    else { $Tier = 'DEEP' }
}

if ($Context -eq 0) {
    $injectedTokens = 0
    foreach ($p in @($instructionRuntimePath, $repoContextRuntimePath, $projectRulesRuntimePath)) {
        if (Test-Path -LiteralPath $p) { $injectedTokens += [Math]::Ceiling((Get-Item -LiteralPath $p).Length / 3.0) }
    }
    # Calibrated 2026-09-07: measured FAST first-request prompt = 7,842 tokens
    # (all-schema pre-budget measured 21,839). Per-tier fixed base below the
    # injected instruction bytes; reserve is a small safety, not a text budget.
    $tierBasePrompt = switch ($Tier) { 'FAST' { 7200 } 'CODE' { 9200 } 'DEEP' { 12500 } }
    $estimatedTokens = $tierBasePrompt + $injectedTokens + 1024
    $ramCap = if ($ramGiB -lt 40) { 32768 } else { 65536 }
    $Context = @(16384, 24576, 32768, 49152, 65536) | Where-Object { $_ -ge $estimatedTokens -and $_ -le $ramCap } | Select-Object -First 1
    if (-not $Context) { $Context = $ramCap }
    $contextReason = "tier=$Tier prompt-est ($estimatedTokens est)"
}
if ($Tier -eq 'FAST') { $OutputLimit = 4096 } elseif ($Context -le 12288) { $OutputLimit = 6144 } else { $OutputLimit = 8192 }
if ($totalVram -le 16384) { $fitTarget = 1024 } else { $fitTarget = 768 }

$projectIdentity = Get-BlackCodeProjectIdentity $projectRoot
$profileEnvelope = New-BlackCodeExecutionProfile -Context $Context -FitTargetMiB $fitTarget
$Port = Find-FreePort 18080 18099
$BaseUrl = "http://127.0.0.1:$Port/v1"; $HealthUrl = "http://127.0.0.1:$Port/health"
$ConfigPath = Join-Path $RuntimeDir "opencode.runtime.json"
$telemetryPluginUri = Convert-ToFileUri (Resolve-RuntimeFile "opencode-telemetry.js")
$governorPluginUri = Convert-ToFileUri (Resolve-RuntimeFile "opencode-governor.js")
switch ($Tier) {
    'FAST' { $toolsAllow = [ordered]@{ read=$true; grep=$true; glob=$true; edit=$true; bash=$true; write=$false; list=$false; todowrite=$false; lsp=$false; task=$false; webfetch=$false; websearch=$false; skill=$false } }
    'CODE' { $toolsAllow = [ordered]@{ read=$true; write=$true; edit=$true; glob=$true; grep=$true; list=$true; bash=$true; todowrite=$true; lsp=$true; task=$false; webfetch=$false; websearch=$false; skill=$false } }
    'DEEP' { $toolsAllow = [ordered]@{ read=$true; write=$true; edit=$true; glob=$true; grep=$true; list=$true; bash=$true; task=$true; todowrite=$true; lsp=$true; webfetch=$true; websearch=$true; skill=$true } }
}
$config = [ordered]@{
    '$schema' = "https://opencode.ai/config.json"
    model = $ModelId
    instructions = @("black-code-execution.md", "repo-context.md", "project-rules.md")
    plugin = @($telemetryPluginUri, $governorPluginUri)
    permission = [ordered]@{ read="allow"; edit="allow"; glob="allow"; grep="allow"; list="allow"; bash="allow"; task="allow"; todowrite="allow"; webfetch="allow"; websearch="allow"; lsp="allow"; skill="allow"; external_directory="ask"; doom_loop="ask" }
    # Tool budget, set by the Prompt Budget Governor. Disabled tools drop out of
    # the model's request schema entirely (verified in opencode-ai runtime:
    # tools.filter((t,i) => user.tools?.[i] !== false ...)), shrinking the boot
    # prompt with each tier. Permission stays allow so behavior is gated by the
    # chosen tier, not by the permission rule.
    tools = $toolsAllow
    provider = [ordered]@{
        $ProviderId = [ordered]@{
            npm = "@ai-sdk/openai-compatible"; name = "BLACK Code Local Qwen 3.8"
            options = [ordered]@{ baseURL=$BaseUrl; apiKey="local" }
            models = [ordered]@{ $ModelAlias = [ordered]@{ name="Qwen3.8-27B Uncensored BLACK 7.27"; reasoning=$false; options=[ordered]@{ chat_template_kwargs=[ordered]@{ enable_thinking=$false } }; limit=[ordered]@{ context=$Context; output=$OutputLimit } } }
        }
    }
}
$config | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $ConfigPath

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stdout = Join-Path $LogDir "llama-$timestamp.out.log"; $stderr = Join-Path $LogDir "llama-$timestamp.err.log"
$telemetryPath = Join-Path $BottleneckDir "tools-$timestamp.jsonl"
$bottleneckPath = Join-Path $BottleneckDir "bottleneck-$timestamp.json"
$serverArgs = @(
    "--model",$ModelPath,
    "--spec-draft-model",$DraftPath,
    "--alias",$ModelAlias,
    "--host","127.0.0.1","--port","$Port",
    "--parallel","1",
    "--ctx-size","$Context",
    "--fit","on","--fit-target","$fitTarget","--fit-ctx","$Context",
    "--cache-type-k","q8_0","--cache-type-v","q8_0",
    "--flash-attn","auto",
    "--spec-type","draft-mtp","--spec-draft-n-max","2","--spec-draft-n-min","0","--spec-draft-p-min","0.0",
    "--jinja"
)

Write-Host ""
Write-Host "BLACK CODE - LOCAL QWEN 3.8 / FIXED 7.27" -ForegroundColor Magenta
Write-Host "Project:   $projectRoot"; Write-Host "GPU:       $gpuName"; Write-Host "VRAM:      $freeVram / $totalVram MiB free"; Write-Host "RAM:       $ramGiB GiB"
Write-Host "Model:     $ModelFile"; Write-Host "Index:     $($repoIndex.index.cache_status) / $trackedFileCount tracked" -ForegroundColor Green
Write-Host "Delta:     $(@($repoIndex.index.changed_files).Count) changed / $(@($repoIndex.index.likely_tests).Count) likely tests"
Write-Host "Rules:     Claude/BLACK bridge active"
Write-Host "Prompt:    Tier $Tier | tool budget + capsule context (Prompt Budget Governor)"
Write-Host "Context:   $Context ($contextReason)"; Write-Host "Output:    $OutputLimit max tokens"
Write-Host ("VRAM fit:  automatic; {0} MiB target headroom" -f $fitTarget)
Write-Host ("Quant:     BLACK UD-IQ2_XXS / {0} GB / locally pinned SHA" -f $modelManifest.model_size_decimal_gb) -ForegroundColor Green
Write-Host "Draft:     Uncensored Q4_0 MTP / max 2" -ForegroundColor Green
Write-Host "N-gram:    OFF"; Write-Host "Cache:     llama default; forced cache-reuse OFF"; Write-Host "Tensor:    pinned 7.27 reference precision map"
Write-Host "Vision:    OFF / no sidecar"
Write-Host "Governor:  hash-bound final verification" -ForegroundColor Green
Write-Host "Telemetry: observation-only auto bottleneck" -ForegroundColor Green
Write-Host "Fabric:    $($profileEnvelope.profile.profile_name) [$($profileEnvelope.canonical_hash.Substring(0, 12))]" -ForegroundColor Green
Write-Host "Files:     autonomous inside this project"; Write-Host "Outside:   approval required"; Write-Host ""

$sessionStartedAt = Get-Date
$startupStartedAt = Get-Date
$server = Start-Process -FilePath $ServerExe -ArgumentList $serverArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$startupMs = 0
$exitCode = 1
$previousTelemetry = $env:BLACK_CODE_TELEMETRY_PATH
$previousGovernorDir = $env:BLACK_CODE_GOVERNOR_DIR
$previousProjectRoot = $env:BLACK_CODE_PROJECT_ROOT
$previousVerifyScript = $env:BLACK_CODE_VERIFY_SCRIPT

try {
    $ready = $false
    for ($i=0; $i -lt 600; $i++) {
        if ($server.HasExited) { if (Test-Path $stderr) { Get-Content $stderr -Tail 150 }; throw "llama-server failed to start." }
        try { if (Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 2) { $ready=$true; break } } catch {}
        if (($i % 10) -eq 0) { Write-Host -NoNewline "." }; Start-Sleep -Seconds 1
    }
    $startupMs = [Math]::Round(((Get-Date) - $startupStartedAt).TotalMilliseconds)
    Write-Host ""
    if (-not $ready) { throw "llama-server did not become healthy." }
    $models = Invoke-RestMethod -Uri "$BaseUrl/models" -TimeoutSec 10
    if (-not $models.data) { throw "llama-server is healthy but /v1/models returned no model." }

    Write-Host "Local model server VERIFIED with BLACK 7.27 + external Uncensored MTP2 + persistent repo delta index." -ForegroundColor Green
    Write-Host "Starting OpenCode with BLACK completion governor..." -ForegroundColor Green; Write-Host ""
    $env:OPENCODE_CONFIG = $ConfigPath
    $env:BLACK_CODE_TELEMETRY_PATH = $telemetryPath
    $env:BLACK_CODE_GOVERNOR_DIR = $GovernorDir
    $env:BLACK_CODE_PROJECT_ROOT = $projectRoot
    $env:BLACK_CODE_VERIFY_SCRIPT = Resolve-RuntimeFile "verification-gate.ps1"
    Refresh-Path
    $opencode = (Get-Command "opencode" -ErrorAction Stop).Source
    & $opencode "." "--model" $ModelId
    $exitCode = $LASTEXITCODE
}
finally {
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue; $server.WaitForExit() }
    if ($null -eq $previousTelemetry) { Remove-Item Env:BLACK_CODE_TELEMETRY_PATH -ErrorAction SilentlyContinue } else { $env:BLACK_CODE_TELEMETRY_PATH = $previousTelemetry }
    if ($null -eq $previousGovernorDir) { Remove-Item Env:BLACK_CODE_GOVERNOR_DIR -ErrorAction SilentlyContinue } else { $env:BLACK_CODE_GOVERNOR_DIR = $previousGovernorDir }
    if ($null -eq $previousProjectRoot) { Remove-Item Env:BLACK_CODE_PROJECT_ROOT -ErrorAction SilentlyContinue } else { $env:BLACK_CODE_PROJECT_ROOT = $previousProjectRoot }
    if ($null -eq $previousVerifyScript) { Remove-Item Env:BLACK_CODE_VERIFY_SCRIPT -ErrorAction SilentlyContinue } else { $env:BLACK_CODE_VERIFY_SCRIPT = $previousVerifyScript }
    $sessionCompletedAt = Get-Date
    $totalMs = [Math]::Round(($sessionCompletedAt - $sessionStartedAt).TotalMilliseconds)
    try { & (Resolve-RuntimeFile "analyze-bottleneck.ps1") -TelemetryPath $telemetryPath -LlamaStderr $stderr -StartupMs $startupMs -TotalMs $totalMs -OutputPath $bottleneckPath }
    catch { Write-Warning "BLACK bottleneck analysis skipped: $($_.Exception.Message)" }
    try { Write-BlackCodeSessionEvidence -EvidenceDir $FabricEvidenceDir -ProfileEnvelope $profileEnvelope -ProjectIdentity $projectIdentity -StartedAt $sessionStartedAt -CompletedAt $sessionCompletedAt -ExitCode $exitCode -GpuName $gpuName -FreeVramMiB $freeVram -TotalVramMiB $totalVram -StdoutLog $stdout -StderrLog $stderr }
    catch { Write-Warning "BLACK Execution Fabric evidence write failed: $($_.Exception.Message)" }
}

exit $exitCode
