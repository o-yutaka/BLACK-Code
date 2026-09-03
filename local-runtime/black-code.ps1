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

$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelFile = "Qwen3.8-27B-Uncensored-IQ4_XS.gguf"
$ModelPath = Join-Path $ModelDir $ModelFile
$ModelAlias = "qwen3.8-27b-uncensored"
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

Ensure-Installed
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$gpuLine = ((Invoke-NvidiaSmi "name,memory.total,memory.free") -split "`r?`n")[0]
$gpuParts = $gpuLine -split ',' | ForEach-Object { $_.Trim() }
$gpuName = $gpuParts[0]
$totalVram = [int]$gpuParts[1]
$freeVram = [int]$gpuParts[2]

$ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$ramGiB = [Math]::Round($ramBytes / 1GB, 1)
if ($Context -eq 0) {
    if ($ramGiB -lt 40) { $Context = 24576 } else { $Context = 32768 }
}

if ($totalVram -le 12288) {
    $fitTarget = 1536
}
elseif ($totalVram -le 16384) {
    $fitTarget = 1280
}
else {
    $fitTarget = 1024
}

$Port = Find-FreePort 18080 18099
$BaseUrl = "http://127.0.0.1:$Port/v1"
$HealthUrl = "http://127.0.0.1:$Port/health"
$ConfigPath = Join-Path $RuntimeDir "opencode.runtime.json"

$config = [ordered]@{
    '$schema' = "https://opencode.ai/config.json"
    model = $ModelId
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
                    name = "Qwen3.8-27B Uncensored IQ4_XS"
                    reasoning = $false
                    options = [ordered]@{
                        chat_template_kwargs = [ordered]@{
                            enable_thinking = $false
                        }
                    }
                    limit = [ordered]@{
                        context = $Context
                        output = 8192
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

# Qwen3.8 embeds MTP layers in this GGUF. Keep MTP speculative decoding
# permanently enabled for BLACK Code. Use a four-token draft window by default.
$serverArgs = @(
    "--model", $ModelPath,
    "--alias", $ModelAlias,
    "--host", "127.0.0.1",
    "--port", "$Port",
    "--parallel", "1",
    "--ctx-size", "$Context",
    "--fit", "on",
    "--fit-target", "$fitTarget",
    "--fit-ctx", "16384",
    "--cache-type-k", "q8_0",
    "--cache-type-v", "q8_0",
    "--flash-attn", "auto",
    "--spec-type", "draft-mtp",
    "--spec-draft-n-max", "4",
    "--spec-draft-n-min", "0",
    "--spec-draft-p-min", "0.0",
    "--jinja"
)

Write-Host ""
Write-Host "BLACK CODE — LOCAL QWEN 3.8" -ForegroundColor Magenta
Write-Host "Project:   $(Get-Location)"
Write-Host "GPU:       $gpuName"
Write-Host "VRAM:      $freeVram / $totalVram MiB free"
Write-Host "RAM:       $ramGiB GiB"
Write-Host "Model:     $ModelFile"
Write-Host "Context:   $Context"
Write-Host "VRAM fit:  automatic; ${fitTarget} MiB target headroom"
Write-Host "MTP:       ALWAYS ON (draft-mtp, max 4)" -ForegroundColor Green
Write-Host "Files:     autonomous inside this project"
Write-Host "Outside:   approval required"
Write-Host ""

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

    Write-Host "Local model server VERIFIED with MTP speculative decoding enabled." -ForegroundColor Green
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
}

exit $exitCode
