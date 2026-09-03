param(
    [switch]$Force,
    [switch]$ForceLlama
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

$ModelRepo = "JonathanColetti/Qwen3.8-27B-Uncensored-GGUF"
$ModelFile = "Qwen3.8-27B-Uncensored-IQ2_M.gguf"
$ModelSha256 = "28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187"
$ModelPath = Join-Path $ModelDir $ModelFile
$ModelUrl = "https://huggingface.co/$ModelRepo/resolve/main/${ModelFile}?download=true"
$ModelMinimumBytes = 10000000000

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
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

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$BinDir"
}

function Require-Command([string]$Name, [string]$Help) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found. $Help"
    }
}

function Download-File([string]$Url, [string]$Destination) {
    $partial = "$Destination.part"
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
    Write-Host "Downloading: $Url"
    Write-Host "To:          $Destination"
    & curl.exe -L --fail --retry 8 --retry-all-errors --retry-delay 2 -C - -o $partial $Url
    if ($LASTEXITCODE -ne 0) {
        throw "curl failed with exit code $LASTEXITCODE"
    }
    Move-Item -Force $partial $Destination
}

function Test-Model([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $item = Get-Item $Path
    if ($item.Length -lt $ModelMinimumBytes) { return $false }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $bytes = New-Object byte[] 4
        [void]$stream.Read($bytes, 0, 4)
        $magic = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($magic -ne "GGUF") { return $false }
    }
    finally {
        $stream.Dispose()
    }

    $hash = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
    return $hash -eq $ModelSha256
}

if ($env:OS -ne "Windows_NT") {
    throw "This runtime is for Windows."
}

New-Item -ItemType Directory -Force -Path $RuntimeDir, $LauncherDir, $BinDir, $LlamaDir, $ModelDir, $DownloadDir, $LogDir | Out-Null

Write-Step "Checking NVIDIA GPU"
Require-Command "nvidia-smi.exe" "Install or update the NVIDIA driver first."
$gpuInfo = Invoke-NvidiaSmi "name,memory.total"
Write-Host $gpuInfo

Write-Step "Checking curl"
Require-Command "curl.exe" "Windows 10/11 normally includes curl.exe."

Write-Step "Installing OpenCode if needed"
Refresh-Path
if (-not (Get-Command "opencode" -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command "npm.cmd" -ErrorAction SilentlyContinue)) {
        $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw "Neither npm nor winget is available. Install Node.js LTS and run setup again."
        }
        & winget.exe install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            throw "Node.js installation failed with exit code $LASTEXITCODE"
        }
        Refresh-Path
    }

    Require-Command "npm.cmd" "Node.js/npm is not visible in PATH."
    & npm.cmd install -g opencode-ai
    if ($LASTEXITCODE -ne 0) {
        throw "OpenCode installation failed with exit code $LASTEXITCODE"
    }
    Refresh-Path
}
Require-Command "opencode" "OpenCode was not found after installation."

Write-Step "Installing llama.cpp Windows CUDA build"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
if ($Force -or $ForceLlama -or -not (Test-Path $ServerExe)) {
    $releases = Invoke-RestMethod -Headers @{ "User-Agent" = "BLACK-Code-Setup" } -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=20"
    $picked = $null

    foreach ($release in $releases) {
        $main = $release.assets | Where-Object { $_.name -match '^llama-b.*-bin-win-cuda-12\.4-x64\.zip$' } | Select-Object -First 1
        $cudart = $release.assets | Where-Object { $_.name -eq 'cudart-llama-bin-win-cuda-12.4-x64.zip' } | Select-Object -First 1
        if ($main -and $cudart) {
            $picked = [PSCustomObject]@{ tag = $release.tag_name; main = $main; cudart = $cudart }
            break
        }
    }

    if (-not $picked) {
        throw "Could not find a recent llama.cpp Windows CUDA 12.4 release."
    }

    Write-Host "llama.cpp release: $($picked.tag)"
    $mainZip = Join-Path $DownloadDir $picked.main.name
    $cudaZip = Join-Path $DownloadDir $picked.cudart.name

    if ($Force -or $ForceLlama -or -not (Test-Path $mainZip)) { Download-File $picked.main.browser_download_url $mainZip }
    if ($Force -or $ForceLlama -or -not (Test-Path $cudaZip)) { Download-File $picked.cudart.browser_download_url $cudaZip }

    $stage = Join-Path $RuntimeDir "llama-stage"
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    New-Item -ItemType Directory -Force -Path (Join-Path $stage "main"), (Join-Path $stage "cuda") | Out-Null

    Expand-Archive -Force -Path $mainZip -DestinationPath (Join-Path $stage "main")
    Expand-Archive -Force -Path $cudaZip -DestinationPath (Join-Path $stage "cuda")

    $foundServer = Get-ChildItem (Join-Path $stage "main") -Recurse -Filter "llama-server.exe" | Select-Object -First 1
    if (-not $foundServer) { throw "llama-server.exe was not found in the downloaded archive." }

    Get-ChildItem $LlamaDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    Copy-Item -Path (Join-Path $foundServer.Directory.FullName "*") -Destination $LlamaDir -Recurse -Force
    Get-ChildItem (Join-Path $stage "cuda") -Recurse -File | ForEach-Object {
        Copy-Item -Force $_.FullName (Join-Path $LlamaDir $_.Name)
    }
    Remove-Item -Recurse -Force $stage
}

if (-not (Test-Path $ServerExe)) { throw "llama-server.exe installation did not complete." }
& $ServerExe --version
if ($LASTEXITCODE -ne 0) { throw "llama-server.exe exists but failed to run." }

Write-Step "Downloading Qwen3.8-27B Uncensored IQ2_M"
if ($Force -or -not (Test-Model $ModelPath)) {
    if (Test-Path $ModelPath) {
        Move-Item -Force $ModelPath "$ModelPath.invalid"
    }
    Download-File $ModelUrl $ModelPath
}

Write-Host "Verifying GGUF SHA-256..."
if (-not (Test-Model $ModelPath)) {
    throw "Model verification failed. Expected SHA256 $ModelSha256"
}
$modelSize = [Math]::Round((Get-Item $ModelPath).Length / 1GB, 2)
Write-Host "Model verified: $ModelFile ($modelSize GiB)"

Write-Step "Installing BLACK Code launcher"
$launcherFiles = @(
    "black-code.ps1",
    "setup.ps1",
    "doctor.ps1",
    "execution-fabric.ps1",
    "black-code-execution.md"
)
foreach ($name in $launcherFiles) {
    $source = Join-Path $PSScriptRoot $name
    if (Test-Path $source) {
        Copy-Item -Force $source (Join-Path $LauncherDir $name)
    }
}

$Shim = Join-Path $BinDir "black-code.cmd"
$InstalledLauncher = Join-Path $LauncherDir "black-code.ps1"
$shimText = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstalledLauncher`" %*`r`n"
Set-Content -Encoding ASCII -Path $Shim -Value $shimText

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ([string]::IsNullOrWhiteSpace($userPath)) { $userPath = "" }
$parts = $userPath.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if ($parts -notcontains $BinDir) {
    [Environment]::SetEnvironmentVariable("Path", (($parts + $BinDir) -join ';'), "User")
}
Refresh-Path

$state = [ordered]@{
    installed_at = (Get-Date).ToString("o")
    model = $ModelFile
    model_sha256 = $ModelSha256
    model_path = $ModelPath
    model_size_gib = $modelSize
    llama_server = $ServerExe
    gpu = ($gpuInfo -join "; ")
    execution_fabric = "black-execution-fabric-iq2m-speed-v1"
    quantization = "IQ2_M"
    speculative = "draft-mtp"
    mtp_draft_max = 2
    ngram_mod = $false
    forced_cache_reuse = $false
}
$state | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $RuntimeDir "state.json")

Write-Host ""
Write-Host "BLACK CODE LOCAL RUNTIME VERIFIED" -ForegroundColor Green
Write-Host "Open a new terminal in any code repository and run:"
Write-Host ""
Write-Host "    black-code" -ForegroundColor Yellow