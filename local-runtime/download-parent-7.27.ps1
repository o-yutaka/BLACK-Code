param(
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [ValidateRange(5,300)][int]$PollSeconds = 15,
    [switch]$StatusOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:LASTEXITCODE = 0

if ($env:OS -ne "Windows_NT") { throw "BLACK Code parent transfer must run in Windows PowerShell." }

$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
if (-not (Test-Path -LiteralPath $LockPath)) { throw "model-7.27.lock.json is missing." }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$SourceDir = Join-Path $WorkDir "uncensored-parent"
$VenvDir = Join-Path $WorkDir ".venv"
$StatePath = Join-Path $WorkDir "parent-download.state.json"
$StdoutPath = Join-Path $WorkDir "parent-download.out.log"
$StderrPath = Join-Path $WorkDir "parent-download.err.log"
$RequiredPeakBytes = 125000000000L

function Get-DirectoryBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0L }
    $sum = 0L
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $sum += [int64]$_.Length }
    return $sum
}

function Get-LatestMtime([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $latest = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    return $latest.LastWriteTimeUtc.ToString("o")
}

function Get-DriveSnapshot {
    $root = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $WorkDir).Path)
    $drive = [IO.DriveInfo]::new($root)
    $parentBytes = Get-DirectoryBytes $SourceDir
    return [ordered]@{
        free_bytes = [int64]$drive.AvailableFreeSpace
        reusable_parent_bytes = [int64]$parentBytes
        effective_bytes = [int64]$drive.AvailableFreeSpace + [int64]$parentBytes
        required_peak_bytes = $RequiredPeakBytes
    }
}

function Write-State([string]$Status,[Nullable[int]]$HfPid,[Nullable[int]]$ExitCode,[string]$ErrorText,[Nullable[int]]$ShardCount) {
    $disk = Get-DriveSnapshot
    $state = [ordered]@{
        schema_version = "1.0"
        status = $Status
        phase = "parent_snapshot"
        updated_at = (Get-Date).ToString("o")
        host = $env:COMPUTERNAME
        supervisor_pid = $PID
        hf_pid = if ($null -eq $HfPid) { $null } else { [int]$HfPid }
        hf_exit_code = if ($null -eq $ExitCode) { $null } else { [int]$ExitCode }
        parent_repo = [string]$Lock.uncensored_parent.repo
        parent_revision = [string]$Lock.uncensored_parent.revision
        work_dir = $WorkDir
        source_dir = $SourceDir
        source_bytes = [int64]$disk.reusable_parent_bytes
        latest_mtime_utc = Get-LatestMtime $SourceDir
        free_bytes = [int64]$disk.free_bytes
        effective_bytes = [int64]$disk.effective_bytes
        required_peak_bytes = $RequiredPeakBytes
        stdout_log = $StdoutPath
        stderr_log = $StderrPath
        shard_count = if ($null -eq $ShardCount) { $null } else { [int]$ShardCount }
        error = if ([string]::IsNullOrWhiteSpace($ErrorText)) { $null } else { $ErrorText }
    }
    $tmp = "$StatePath.tmp-$PID"
    $state | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $tmp
    Move-Item -Force -LiteralPath $tmp -Destination $StatePath
}

function Test-ProcessAlive([Nullable[int]]$ProcessId) {
    if ($null -eq $ProcessId -or $ProcessId -le 0) { return $false }
    return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Assert-HfSnapshotComplete([string]$Path) {
    $config = Join-Path $Path "config.json"
    if (-not (Test-Path -LiteralPath $config)) { throw "Parent snapshot incomplete: config.json missing." }
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
        if ($missing.Count -gt 0) { throw "Parent snapshot incomplete; missing/empty shards: $([string]::Join(', ', @($missing | Select-Object -First 20)))" }
        return $shards.Count
    }
    $single = @(Get-ChildItem -LiteralPath $Path -Filter "*.safetensors" -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
    if ($single.Count -lt 1) { throw "Parent snapshot incomplete: no safetensors files found." }
    return $single.Count
}

function Show-State {
    if (-not (Test-Path -LiteralPath $StatePath)) {
        [pscustomobject]@{ status = "NO_STATE"; work_dir = $WorkDir; source_dir = $SourceDir; source_bytes = Get-DirectoryBytes $SourceDir; state_file = $StatePath }
        return
    }
    $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    $hfAlive = Test-ProcessAlive ([Nullable[int]]$state.hf_pid)
    [pscustomobject]@{
        status = [string]$state.status
        hf_pid = $state.hf_pid
        hf_alive = $hfAlive
        work_dir = $WorkDir
        source_dir = $SourceDir
        source_bytes = Get-DirectoryBytes $SourceDir
        latest_mtime_utc = Get-LatestMtime $SourceDir
        stdout_log = $StdoutPath
        stderr_log = $StderrPath
        state_file = $StatePath
    }
}

New-Item -ItemType Directory -Force -Path $WorkDir,$SourceDir | Out-Null

if ($StatusOnly) {
    Show-State | Format-List
    return
}

# If another BLACK Code transfer is already alive, attach by observation instead of spawning a duplicate.
$existingPid = $null
if (Test-Path -LiteralPath $StatePath) {
    try {
        $existingState = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
        if ([string]$existingState.parent_revision -eq [string]$Lock.uncensored_parent.revision -and (Test-ProcessAlive ([Nullable[int]]$existingState.hf_pid))) {
            $existingPid = [int]$existingState.hf_pid
        }
    } catch { $existingPid = $null }
}

if ($null -ne $existingPid) {
    Write-Host "[7.27] attaching to existing HF parent transfer PID $existingPid" -ForegroundColor Yellow
    while (Test-ProcessAlive ([Nullable[int]]$existingPid)) {
        Write-State "DOWNLOADING" ([Nullable[int]]$existingPid) $null "" $null
        $bytes = Get-DirectoryBytes $SourceDir
        Write-Host ("[7.27] existing transfer alive pid={0} parent={1:N2} GiB latest={2}" -f $existingPid,($bytes/1GB),(Get-LatestMtime $SourceDir))
        Start-Sleep -Seconds $PollSeconds
    }
    try {
        $count = Assert-HfSnapshotComplete $SourceDir
        Write-State "COMPLETE" $null 0 "" ([Nullable[int]]$count)
        Write-Host "[7.27] existing parent transfer completed and snapshot is valid ($count shard/file entries)." -ForegroundColor Green
        return
    } catch {
        Write-Host "[7.27] previous transfer ended before snapshot completion; resuming safely." -ForegroundColor Yellow
    }
}

# A complete snapshot never needs to be downloaded again.
try {
    $count = Assert-HfSnapshotComplete $SourceDir
    Write-State "COMPLETE" $null 0 "" ([Nullable[int]]$count)
    Write-Host "[7.27] parent snapshot already complete; download skipped." -ForegroundColor Green
    return
} catch { }

$disk = Get-DriveSnapshot
if ([int64]$disk.effective_bytes -lt $RequiredPeakBytes) {
    Write-State "BLOCKED_DISK" $null $null "effective build capacity is below 125000000000 bytes" $null
    throw ("7.27 build needs at least 125 GB effective capacity; free={0:N2} GiB reusable={1:N2} GiB effective={2} bytes" -f ([int64]$disk.free_bytes/1GB),([int64]$disk.reusable_parent_bytes/1GB),[int64]$disk.effective_bytes)
}

$PythonCommand = Get-Command "python.exe" -ErrorAction SilentlyContinue
if (-not $PythonCommand) { throw "Windows python.exe was not found." }
if (-not (Test-Path -LiteralPath (Join-Path $VenvDir "Scripts\python.exe"))) {
    Write-State "PREPARING" $null $null "" $null
    & $PythonCommand.Source -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { throw "create build venv failed with exit code $LASTEXITCODE" }
}
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
& $VenvPython -m pip install --disable-pip-version-check --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed with exit code $LASTEXITCODE" }
& $VenvPython -m pip install --disable-pip-version-check "huggingface_hub[hf_xet]"
if ($LASTEXITCODE -ne 0) { throw "huggingface_hub[hf_xet] install failed with exit code $LASTEXITCODE" }
$Hf = Join-Path $VenvDir "Scripts\hf.exe"
if (-not (Test-Path -LiteralPath $Hf)) { throw "hf.exe was not installed in the Windows build venv." }

$previousXet = $env:HF_XET_HIGH_PERFORMANCE
$previousTimeout = $env:HF_HUB_DOWNLOAD_TIMEOUT
$env:HF_XET_HIGH_PERFORMANCE = "1"
$env:HF_HUB_DOWNLOAD_TIMEOUT = "600"
try {
    Add-Content -LiteralPath $StdoutPath -Value ("`n=== BLACK Code parent transfer {0} ===" -f (Get-Date).ToString("o"))
    Add-Content -LiteralPath $StderrPath -Value ("`n=== BLACK Code parent transfer {0} ===" -f (Get-Date).ToString("o"))
    $args = @("download",[string]$Lock.uncensored_parent.repo,"--revision",[string]$Lock.uncensored_parent.revision,"--local-dir",$SourceDir)
    $process = Start-Process -FilePath $Hf -ArgumentList $args -WorkingDirectory $env:SystemRoot -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    Write-State "DOWNLOADING" ([Nullable[int]]$process.Id) $null "" $null
    Write-Host "[7.27] HF parent transfer started: PID $($process.Id)" -ForegroundColor Cyan
    Write-Host "[7.27] durable state: $StatePath"
    Write-Host "[7.27] stdout: $StdoutPath"
    Write-Host "[7.27] stderr: $StderrPath"

    while (-not $process.HasExited) {
        Write-State "DOWNLOADING" ([Nullable[int]]$process.Id) $null "" $null
        $bytes = Get-DirectoryBytes $SourceDir
        Write-Host ("[7.27] downloading pid={0} parent={1:N2} GiB latest={2}" -f $process.Id,($bytes/1GB),(Get-LatestMtime $SourceDir))
        Start-Sleep -Seconds $PollSeconds
        $process.Refresh()
    }
    $exitCode = $process.ExitCode
    if ($exitCode -ne 0) {
        $detail = if (Test-Path -LiteralPath $StderrPath) { (Get-Content -Tail 40 -LiteralPath $StderrPath -ErrorAction SilentlyContinue) -join "`n" } else { "" }
        Write-State "FAILED" $null ([Nullable[int]]$exitCode) $detail $null
        throw "HF parent transfer failed with exit code $exitCode. See $StderrPath"
    }

    $count = Assert-HfSnapshotComplete $SourceDir
    Write-State "COMPLETE" $null ([Nullable[int]]0) "" ([Nullable[int]]$count)
    Write-Host "[7.27] parent snapshot COMPLETE: $count safetensor shard/file entries" -ForegroundColor Green
} finally {
    if ($null -eq $previousXet) { Remove-Item Env:HF_XET_HIGH_PERFORMANCE -ErrorAction SilentlyContinue } else { $env:HF_XET_HIGH_PERFORMANCE = $previousXet }
    if ($null -eq $previousTimeout) { Remove-Item Env:HF_HUB_DOWNLOAD_TIMEOUT -ErrorAction SilentlyContinue } else { $env:HF_HUB_DOWNLOAD_TIMEOUT = $previousTimeout }
}
