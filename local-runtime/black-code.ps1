param(
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

$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelFile = "Qwen3.8-27B-Uncensored-IQ2_M.gguf"
$ModelPath = Join-Path $ModelDir $ModelFile
$ModelAlias = "qwen3.8-27b-uncensored-iq2m"
$ProviderId = "black-local"
$ModelId = "$ProviderId/$ModelAlias"

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$BinDir"
}

function Invoke-NvidiaSmi([string]$Query) {
    $stdout = [IO.Path]::GetTempFileName()
    $stderr = [IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath (Get-Command "nvidia-smi.exe").Source `
            -ArgumentList "--query-gpu=$Query", "--format=csv,noheader,nounits" `
            -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output = (Get-Content -Raw -Path $stdout -ErrorAction SilentlyContinue).Trim()
        if ($process.ExitCode -ne 0 -or -not $output) {
            $detail = (Get-Content -Raw -Path $stderr -ErrorAction SilentlyContinue).Trim()
            throw "nvidia-smi failed with exit code $($process.ExitCode): $detail"
        }
        return $output
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr
    }
}

function Find-FreePort([int]$Start, [int]$End) {
    for ($p = $Start; $p -le $End; $p++) {
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
            $listener.Start()
            $listener.Stop()
            return $p
        }
        catch {}
    }
    throw "No free local port found in range $Start-$End."
}

function Resolve-SetupScript {
    $near = Join-Path $PSScriptRoot "setup.ps1"
    if (Test-Path $near) { return $near }
    $installed = Join-Path $LauncherDir "setup.ps1"
    if (Test-Path $installed) { return $installed }
    throw "setup.ps1 was not found. Re-clone BLACK-Code or restore the local launcher."
}

function Ensure-Installed {
    Refresh-Path
    $opencode = Get-Command "opencode" -ErrorAction SilentlyContinue
    if (-not (Test-Path $ServerExe) -or -not (Test-Path $ModelPath) -or -not $opencode) {
        Write-Host "Local runtime is incomplete. Running BLACK Code setup..." -ForegroundColor Yellow
        & (Resolve-SetupScript)
        if ($LASTEXITCODE -ne 0) { throw "BLACK Code setup failed." }
        Refresh-Path
    }
}

function Resolve-FabricFile([string]$Name) {
    $near = Join-Path $PSScriptRoot $Name
    if (Test-Path $near) { return $near }
    $installed = Join-Path $LauncherDir $Name
    if (Test-Path $installed) { return $installed }
    throw "$Name was not found. Run BLACK Code setup from the latest repository checkout."
}

function Get-BlackCodeTrackedFileCount([string]$ProjectRoot) {
    $git = Get-Command "git.exe" -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command "git" -ErrorAction SilentlyContinue }
    if (-not $git) { return $null }

    try {
        $files = @(& $git.Source -C $ProjectRoot ls-files 2>$null)
        if ($LASTEXITCODE -eq 0) { return $files.Count }
    }
    catch {}
    return $null
}

Ensure-Installed
New-Item -ItemType Directory -Force -Path $LogDir, $FabricEvidenceDir | Out-Null

$fabricScript = Resolve-FabricFile "execution-fabric.ps1"
. $fabricScript
$instructionSource = Resolve-FabricFile "black-code-execution.md"
$instructionRuntimePath = Join-Path $RuntimeDir "black-code-execution.md"
Copy-Item -Force $instructionSource $instructionRuntimePath

$gpuLine = ((Invoke-NvidiaSmi "name,memory.total,memory.free") -split "`r?`n")[0]
$gpuParts = $gpuLine -split ',' | ForEach-Object { $_.Trim() }
$gpuName = $gpuParts[0]
$totalVram = [int]$gpuParts[1]
$freeVram = [int]$gpuParts[2]

$ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$ramGiB = [Math]::Round($ramBytes / 1GB, 1)
$projectRoot = (Get-Location).Path
$trackedFileCount = Get-BlackCodeTrackedFileCount $projectRoot
$contextReason = "explicit"

if ($Context -eq 0) {
    if ($totalVram -le 12288) {
        if ($null -ne $trackedFileCount -and $trackedFileCount -le 150) {
            $Context = 8192
            $contextReason = "auto-small-repo"
        }
        elseif ($null -ne $trackedFileCount -and $trackedFileCount -le 800) {
            $Context = 12288
            $contextReason = "auto-medium-repo"
        }
        else {
            $Context = 16384
            $contextReason = "auto-large-repo"
        }
    }
    elseif ($ramGiB -lt 40) {
        $Context = 24576
        $contextReason = "auto-ram"
    }
    else {
        $Context = 32768
        $contextReason = "auto-ram"
    }
}

if ($Context -le 8192) {
    $OutputLimit = 4096
}
elseif ($Context -le 12288) {
    $OutputLimit = 6144
}
else {
    $OutputLimit = 8192
}

if ($totalVram -le 16384) {
    $fitTarget = 1024
}
else {
    $fitTarget = 768
}

$projectIdentity = Get-BlackCodeProjectIdentity $projectRoot
$profileEnvelope = New-BlackCodeExecutionProfile -Context $Context -FitTargetMiB $fitTarget

$Port = Find-FreePort 18080 18099
$BaseUrl = "http://127.0.0.1:$Port/v1"
$HealthUrl = "http://127.0.0.1:$Port/health"
$ConfigPath = Join-Path $RuntimeDir "opencode.runtime.json"

$config = [ordered]@{
    '$schema' = "https://opencode.ai/config.json"
    model = $ModelId
    instructions = @("black-code-execution.md")
    permission = [ordered]@{
        read = "allow"
        edit = "allow"
        glob = "allow"
        grep = "allow"
        list = "allow"
        bash = "allow"
        task = "allow"
        todowrite = "allow"
        webfetch = "allow"
        websearch = "allow"
        lsp = "allow"
        skill = "allow"
        external_directory = "ask"
        doom_loop = "ask"
    }
    provider = [ordered]@{
        $ProviderId = [ordered]@{
            npm = "@ai-sdk/openai-compatible"
            name = "BLACK Code Local Qwen 3.8"
            options = [ordered]@{
                baseURL = $BaseUrl
                apiKey = "local"
            }
            models = [ordered]@{
                $ModelAlias = [ordered]@{
                    name = "Qwen3.8-27B Uncensored IQ2_M"
                    reasoning = $false
                    options = [ordered]@{
                        chat_template_kwargs = [ordered]@{
                            enable_thinking = $false
                        }
                    }
                    limit = [ordered]@{
                        context = $Context
                        output = $OutputLimit
                    }
                }
            }
        }
    }
}
$config | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $ConfigPath

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stdout = Join-Path $LogDir "llama-$timestamp.out.log"
$stderr = Join-Path $LogDir "llama-$timestamp.err.log"

# IQ2_M speed profile:
# - 10.6 GB quant keeps substantially more of the 27B model on a 12 GB RTX 3060.
# - Auto context avoids paying 16K KV/prefill cost for small repositories.
# - Fused Qwen3.8 MTP stays on at n_max=2, the publisher's fastest tested IQ2_M code width.
# - ngram-mod, forced cache-reuse, and explicit tensor split stay disabled.
$serverArgs = @(
    "--model", $ModelPath,
    "--alias", $ModelAlias,
    "--host", "127.0.0.1",
    "--port", "$Port",
    "--parallel", "1",
    "--ctx-size", "$Context",
    "--fit", "on",
    "--fit-target", "$fitTarget",
    "--fit-ctx", "$Context",
    "--cache-type-k", "q8_0",
    "--cache-type-v", "q8_0",
    "--flash-attn", "auto",
    "--spec-type", "draft-mtp",
    "--spec-draft-n-max", "2",
    "--spec-draft-n-min", "0",
    "--spec-draft-p-min", "0.0",
    "--jinja"
)

Write-Host ""
Write-Host "BLACK CODE - LOCAL QWEN 3.8" -ForegroundColor Magenta
Write-Host "Project:   $projectRoot"
Write-Host "GPU:       $gpuName"
Write-Host "VRAM:      $freeVram / $totalVram MiB free"
Write-Host "RAM:       $ramGiB GiB"
Write-Host "Model:     $ModelFile"
Write-Host "Files:     $trackedFileCount tracked"
Write-Host "Context:   $Context ($contextReason)"
Write-Host "Output:    $OutputLimit max tokens"
Write-Host ("VRAM fit:  automatic; {0} MiB target headroom" -f $fitTarget)
Write-Host "Quant:     IQ2_M 10.6 GB speed/memory profile" -ForegroundColor Green
Write-Host "Spec:      MTP max 2 ALWAYS ON" -ForegroundColor Green
Write-Host "N-gram:    OFF"
Write-Host "Cache:     llama default; forced cache-reuse OFF"
Write-Host "Tensor:    automatic; explicit split OFF"
Write-Host "Fabric:    $($profileEnvelope.profile.profile_name) [$($profileEnvelope.canonical_hash.Substring(0, 12))]" -ForegroundColor Green
Write-Host "Files:     autonomous inside this project"
Write-Host "Outside:   approval required"
Write-Host ""

$sessionStartedAt = Get-Date
$server = Start-Process -FilePath $ServerExe -ArgumentList $serverArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$exitCode = 1

try {
    $ready = $false
    for ($i = 0; $i -lt 600; $i++) {
        if ($server.HasExited) {
            Write-Host "llama-server exited during startup." -ForegroundColor Red
            if (Test-Path $stderr) { Get-Content $stderr -Tail 150 }
            throw "llama-server failed to start."
        }

        try {
            $health = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 2
            if ($health) {
                $ready = $true
                break
            }
        }
        catch {}

        if (($i % 10) -eq 0) { Write-Host -NoNewline "." }
        Start-Sleep -Seconds 1
    }

    Write-Host ""
    if (-not $ready) { throw "llama-server did not become healthy." }

    $models = Invoke-RestMethod -Uri "$BaseUrl/models" -TimeoutSec 10
    if (-not $models.data) {
        throw "llama-server is healthy but /v1/models returned no model."
    }

    Write-Host "Local model server VERIFIED with IQ2_M + BLACK Execution Fabric." -ForegroundColor Green
    Write-Host "Starting OpenCode with autonomous project editing..." -ForegroundColor Green
    Write-Host ""

    $env:OPENCODE_CONFIG = $ConfigPath
    Refresh-Path
    $opencode = (Get-Command "opencode" -ErrorAction Stop).Source
    & $opencode "." "--model" $ModelId
    $exitCode = $LASTEXITCODE
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        $server.WaitForExit()
    }

    $sessionCompletedAt = Get-Date
    try {
        Write-BlackCodeSessionEvidence `
            -EvidenceDir $FabricEvidenceDir `
            -ProfileEnvelope $profileEnvelope `
            -ProjectIdentity $projectIdentity `
            -StartedAt $sessionStartedAt `
            -CompletedAt $sessionCompletedAt `
            -ExitCode $exitCode `
            -GpuName $gpuName `
            -FreeVramMiB $freeVram `
            -TotalVramMiB $totalVram `
            -StdoutLog $stdout `
            -StderrLog $stderr
    }
    catch {
        Write-Warning "BLACK Execution Fabric evidence write failed: $($_.Exception.Message)"
    }
}

exit $exitCode
