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
        throw "BLACK Code canonical runtime is native Windows only. Docker, Linux and WSL are not runtime dependencies. Open Windows PowerShell directly and run the native entrypoint."
    }

    if ($env:WSL_INTEROP -or $env:WSL_DISTRO_NAME) {
        throw "WSL interop detected. BLACK Code intentionally refuses WSL-to-Windows bridge execution. Open a native Windows PowerShell/CMD session and run BLACK-Code-Native.cmd or setup-resumable-7.27.ps1 there."
    }

    $cwd = (Get-Location).Path
    if ($cwd -match '^(?i)\\\\(?:wsl\$|wsl\.localhost)\\') {
        throw "BLACK Code cannot run from a WSL UNC working directory: $cwd. Use a native Windows path such as C:\\Users\\... instead."
    }

    if (-not $env:LOCALAPPDATA -or $env:LOCALAPPDATA -notmatch '^[A-Za-z]:\\') {
        throw "LOCALAPPDATA is not a native Windows drive path: $env:LOCALAPPDATA"
    }

    $processPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if (-not $processPath -or $processPath -notmatch '^[A-Za-z]:\\') {
        throw "Current PowerShell host is not a native Windows executable: $processPath"
    }

    $chain = @(Get-BlackCodeProcessChain)
    $bridge = $chain | Where-Object {
        $name = [string]$_.Name
        $cmd = [string]$_.CommandLine
        $name -match '^(?i)(wsl|wslhost|bash|docker|com\.docker\..*)\.exe$' -or
        $cmd -match '(?i)\\wsl\.exe\b|\\wslhost\.exe\b|Docker Desktop|com\.docker'
    } | Select-Object -First 1
    if ($bridge) {
        throw "Non-native controller detected in process ancestry: $($bridge.Name) PID=$($bridge.ProcessId). BLACK Code no longer supports Docker/WSL-controlled canonical execution. Start it from native Windows PowerShell/CMD."
    }

    if (-not $Quiet) {
        Write-Host "BLACK Code native Windows boundary VERIFIED" -ForegroundColor Green
        Write-Host "Host: $processPath"
        Write-Host "Work: $cwd"
    }
}

Assert-BlackCodeNativeWindows
