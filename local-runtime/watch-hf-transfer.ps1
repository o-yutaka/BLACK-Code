param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$SourceDir,
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$SourcePattern,
    [string]$StdoutPath,
    [string]$StderrPath,
    [ValidateRange(1,300)][int]$PollSeconds = 15,
    [ValidateRange(5,7200)][int]$StallSeconds = 900,
    [switch]$StopOnStall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if ($env:OS -ne "Windows_NT") { throw "watch-hf-transfer.ps1 must run in Windows PowerShell, not WSL/Linux." }

function Get-FileSignal([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ bytes = 0L; latest_ticks = 0L; latest_utc = $null }
    }
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { return [pscustomobject]@{ bytes = 0L; latest_ticks = 0L; latest_utc = $null } }
    return [pscustomobject]@{
        bytes = [int64]$item.Length
        latest_ticks = [int64]$item.LastWriteTimeUtc.Ticks
        latest_utc = $item.LastWriteTimeUtc.ToString("o")
    }
}

function Get-DirectorySignal([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ bytes = 0L; latest_ticks = 0L; latest_utc = $null }
    }
    $sum = 0L
    $latestTicks = 0L
    $latestUtc = $null
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $sum += [int64]$_.Length
        if ($_.LastWriteTimeUtc.Ticks -gt $latestTicks) {
            $latestTicks = [int64]$_.LastWriteTimeUtc.Ticks
            $latestUtc = $_.LastWriteTimeUtc.ToString("o")
        }
    }
    return [pscustomobject]@{ bytes = [int64]$sum; latest_ticks = [int64]$latestTicks; latest_utc = $latestUtc }
}

function Get-ProcessSnapshot {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
}

function Get-ProcessTree([int]$RootPid,[object[]]$Snapshot) {
    $ids = [System.Collections.Generic.List[int]]::new()
    [void]$ids.Add($RootPid)
    $index = 0
    while ($index -lt $ids.Count) {
        $parent = $ids[$index]
        foreach ($child in @($Snapshot | Where-Object { [int]$_.ParentProcessId -eq $parent })) {
            $childId = [int]$child.ProcessId
            if (-not $ids.Contains($childId)) { [void]$ids.Add($childId) }
        }
        $index++
    }
    return @($ids)
}

function Get-TreeTransferSignal([int[]]$Ids,[object[]]$Snapshot) {
    $read = 0L
    $write = 0L
    $other = 0L
    foreach ($id in $Ids) {
        $p = $Snapshot | Where-Object { [int]$_.ProcessId -eq $id } | Select-Object -First 1
        if ($p) {
            if ($null -ne $p.ReadTransferCount) { $read += [int64]$p.ReadTransferCount }
            if ($null -ne $p.WriteTransferCount) { $write += [int64]$p.WriteTransferCount }
            if ($null -ne $p.OtherTransferCount) { $other += [int64]$p.OtherTransferCount }
        }
    }
    return [pscustomobject]@{ read = $read; write = $write; other = $other; total = ($read + $write + $other) }
}

function Stop-VerifiedProcessTree([int]$RootPid,[string]$RepoPattern,[string]$SourceRegex) {
    $snapshot = Get-ProcessSnapshot
    $root = $snapshot | Where-Object { [int]$_.ProcessId -eq $RootPid } | Select-Object -First 1
    if (-not $root) { return }
    $commandLine = [string]$root.CommandLine
    if (-not $commandLine -or $commandLine -notmatch $RepoPattern) { throw "Refusing to stop PID $RootPid because its command line no longer matches the pinned repo." }
    if ($SourceRegex -and $commandLine -notmatch $SourceRegex) { throw "Refusing to stop PID $RootPid because its command line no longer matches the expected SourceDir." }
    $tree = @(Get-ProcessTree $RootPid $snapshot)
    foreach ($id in @($tree | Sort-Object -Descending)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

$repoPattern = [regex]::Escape($Repo)
$sourceRegex = if ($SourcePattern) { [regex]::Escape($SourcePattern) } else { $null }
$started = Get-Date
$lastProgress = Get-Date
$previous = $null

while ($true) {
    $snapshot = Get-ProcessSnapshot
    $root = $snapshot | Where-Object { [int]$_.ProcessId -eq $ProcessId } | Select-Object -First 1
    if (-not $root) {
        [ordered]@{
            schema_version = "1.0"
            verdict = "EXITED"
            process_id = $ProcessId
            observed_seconds = [int]((Get-Date) - $started).TotalSeconds
            idle_seconds = [int]((Get-Date) - $lastProgress).TotalSeconds
        } | ConvertTo-Json -Depth 5
        exit 0
    }

    $commandLine = [string]$root.CommandLine
    if (-not $commandLine -or $commandLine -notmatch $repoPattern -or ($sourceRegex -and $commandLine -notmatch $sourceRegex)) {
        [ordered]@{
            schema_version = "1.0"
            verdict = "PROCESS_MISMATCH"
            process_id = $ProcessId
            command_line = $commandLine
        } | ConvertTo-Json -Depth 5
        exit 0
    }

    $treeIds = @(Get-ProcessTree $ProcessId $snapshot)
    $transfer = Get-TreeTransferSignal $treeIds $snapshot
    $source = Get-DirectorySignal $SourceDir
    $stdout = Get-FileSignal $StdoutPath
    $stderr = Get-FileSignal $StderrPath
    $current = [pscustomobject]@{
        source_bytes = [int64]$source.bytes
        source_ticks = [int64]$source.latest_ticks
        stdout_bytes = [int64]$stdout.bytes
        stdout_ticks = [int64]$stdout.latest_ticks
        stderr_bytes = [int64]$stderr.bytes
        stderr_ticks = [int64]$stderr.latest_ticks
        transfer_total = [int64]$transfer.total
    }

    if ($null -eq $previous -or
        $current.source_bytes -ne $previous.source_bytes -or
        $current.source_ticks -ne $previous.source_ticks -or
        $current.stdout_bytes -ne $previous.stdout_bytes -or
        $current.stdout_ticks -ne $previous.stdout_ticks -or
        $current.stderr_bytes -ne $previous.stderr_bytes -or
        $current.stderr_ticks -ne $previous.stderr_ticks -or
        $current.transfer_total -ne $previous.transfer_total) {
        $lastProgress = Get-Date
        $previous = $current
    }

    $idleSeconds = [int]((Get-Date) - $lastProgress).TotalSeconds
    if ($idleSeconds -ge $StallSeconds) {
        $verdict = "STALLED"
        if ($StopOnStall) {
            Stop-VerifiedProcessTree $ProcessId $repoPattern $sourceRegex
            $verdict = "STALLED_STOPPED"
        }
        [ordered]@{
            schema_version = "1.0"
            verdict = $verdict
            process_id = $ProcessId
            observed_seconds = [int]((Get-Date) - $started).TotalSeconds
            idle_seconds = $idleSeconds
            stall_seconds = $StallSeconds
            source_bytes = [int64]$source.bytes
            source_latest_write_utc = $source.latest_utc
            stdout_bytes = [int64]$stdout.bytes
            stderr_bytes = [int64]$stderr.bytes
            process_tree_transfer_total = [int64]$transfer.total
        } | ConvertTo-Json -Depth 5
        exit 0
    }

    Start-Sleep -Seconds $PollSeconds
}
