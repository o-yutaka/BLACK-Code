param(
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-BlackCodeProcessChain {
    $items = [System.Collections.Generic.List[object]]::new()
    $current = Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue
    $seen = [System.Collections.Generic.HashSet[int]]::new()
    for ($i = 0; $i -lt 8 -and $current; $i++) {
        if (-not $seen.Add([int]$current.ProcessId)) { break }
        [void]$items.Add($current)
        if ([int]$current.ParentProcessId -le 0) { break }
        $current = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$current.ParentProcessId)" -ErrorAction SilentlyContinue
    }
    return @($items)
}

function Assert-BlackCodeNativeWindows {
    if ($env:OS -ne "Windows_NT") {
        throw "BLACK Code runtime must execute with native Windows binaries. Docker/Linux runtime execution is unsupported. WSL may control the Windows entrypoint through powershell.exe/cmd.exe."
    }

    if (-not $env:LOCALAPPDATA -or $env:LOCALAPPDATA -notmatch '^[A-Za-z]:\\') {
        throw "LOCALAPPDATA is not a native Windows drive path: $env:LOCALAPPDATA"
    }

    $processPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if (-not $processPath -or $processPath -notmatch '^[A-Za-z]:\\') {
        throw "Current PowerShell host is not a native Windows executable: $processPath"
    }

    $cwd = (Get-Location).Path
    if ($cwd -match '^(?i)\\\\(?:wsl\$|wsl\.localhost)\\') {
        if (-not $Quiet) {
            Write-Host "WSL UNC working directory detected; Windows runtime remains canonical." -ForegroundColor Yellow
        }
    }

    $chain = @(Get-BlackCodeProcessChain)
    $docker = $chain | Where-Object {
        $name = [string]$_.Name
        $cmd = [string]$_.CommandLine
        $name -match '^(?i)(docker|com\.docker\..*)\.exe$' -or
        $cmd -match '(?i)Docker Desktop|com\.docker|\\docker\.exe\b'
    } | Select-Object -First 1
    if ($docker) {
        throw "Docker-controlled execution detected: $($docker.Name) PID=$($docker.ProcessId). BLACK Code intentionally has no Docker runtime/build dependency. Launch the Windows entrypoint directly, including from WSL via powershell.exe/cmd.exe if desired."
    }

    if (-not $Quiet) {
        $controller = if ($env:WSL_INTEROP -or $env:WSL_DISTRO_NAME) { "WSL -> Windows bridge allowed" } else { "Windows native" }
        Write-Host "BLACK Code Windows runtime boundary VERIFIED" -ForegroundColor Green
        Write-Host "Host:       $processPath"
        Write-Host "Work:       $cwd"
        Write-Host "Controller: $controller"
        Write-Host "Docker:     not in execution ancestry"
    }
}

Assert-BlackCodeNativeWindows
