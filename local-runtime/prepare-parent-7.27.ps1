param(
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [ValidateRange(5,300)][int]$PollSeconds = 15,
    [switch]$StatusOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:LASTEXITCODE = 0

if ($env:OS -ne "Windows_NT") { throw "prepare-parent-7.27.ps1 must run in Windows PowerShell, not WSL/Linux." }

$LockPath = Join-Path $PSScriptRoot "model-7.27.lock.json"
if (-not (Test-Path -LiteralPath $LockPath)) { throw "model-7.27.lock.json is missing." }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$SourceDir = Join-Path $WorkDir "uncensored-parent"
$VenvDir = Join-Path $WorkDir ".venv"
$StatePath = Join-Path $WorkDir "parent-download-state.json"
$StdoutPath = Join-Path $WorkDir "parent-download.stdout.log"
$StderrPath = Join-Path $WorkDir "parent-download.stderr.log"

function Require-Command([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required Windows command missing: $Name" }
    return $command.Source
}

function Get-DirectoryBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0L }
    $sum = 0L
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $sum += [int64]$_.Length }
    return $sum
}

function Get-LatestWrite([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $latest = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    return $latest.LastWriteTimeUtc.ToString("o")
}

function Get-SnapshotStatus([string]$Path) {
    $config = Join-Path $Path "config.json"
    $indexPath = Join-Path $Path "model.safetensors.index.json"
    $expected = 0
    $missing = 0
    $complete = $false
    if (Test-Path -LiteralPath $indexPath) {
        try {
            $index = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
            $shards = @($index.weight_map.PSObject.Properties | ForEach-Object { [string]$_.Value } | Sort-Object -Unique)
            $expected = $shards.Count
            foreach ($shard in $shards) {
                $shardPath = Join-Path $Path $shard
                if (-not (Test-Path -LiteralPath $shardPath) -or (Get-Item -LiteralPath $shardPath).Length -le 0) { $missing++ }
            }
            $complete = (Test-Path -LiteralPath $config) -and $expected -gt 0 -and $missing -eq 0
        } catch {
            $complete = $false
        }
    } else {
        $single = @(Get-ChildItem -LiteralPath $Path -Filter "*.safetensors" -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
        $expected = $single.Count
        $complete = (Test-Path -LiteralPath $config) -and $single.Count -gt 0
    }
    return [pscustomobject]@{
        complete = $complete
        expected_shards = $expected
        missing_or_empty_shards = $missing
    }
}

function Write-State([string]$Phase,[string]$Status,[object]$HfPid,[string]$Detail) {
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $snapshot = Get-SnapshotStatus $SourceDir
    $root = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $WorkDir).Path)
    $drive = [IO.DriveInfo]::new($root)
    $parentBytes = Get-DirectoryBytes $SourceDir
    $state = [ordered]@{
        schema_version = "1.0"
        updated_at = (Get-Date).ToString("o")
        phase = $Phase
        status = $Status
        windows_host = $true
        controller_pid = $PID
        hf_pid = if ($null -ne $HfPid) { [int]$HfPid } else { $null }
        repo = [string]$Lock.uncensored_parent.repo
        revision = [string]$Lock.uncensored_parent.revision
        work_dir = $WorkDir
        source_dir = $SourceDir
        parent_bytes = [int64]$parentBytes
        latest_write_utc = Get-LatestWrite $SourceDir
        snapshot_complete = [bool]$snapshot.complete
        expected_shards = [int]$snapshot.expected_shards
        missing_or_empty_shards = [int]$snapshot.missing_or_empty_shards
        free_bytes = [int64]$drive.AvailableFreeSpace
        effective_bytes = [int64]$drive.AvailableFreeSpace + [int64]$parentBytes
        required_effective_bytes = 125000000000L
        detail = $Detail
        stdout_log = $StdoutPath
        stderr_log = $StderrPath
    }
    $temp = "$StatePath.tmp-$PID"
    $state | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $temp
    Move-Item -Force -LiteralPath $temp -Destination $StatePath
}

function Assert-SnapshotComplete([string]$Path) {
    $snapshot = Get-SnapshotStatus $Path
    if (-not $snapshot.complete) {
        throw "Parent snapshot incomplete: expected=$($snapshot.expected_shards) missing_or_empty=$($snapshot.missing_or_empty_shards)"
    }
}

function Get-ActiveParentTransfers {
    $repoPattern = [regex]::Escape([string]$Lock.uncensored_parent.repo)
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -match 'hf\.exe' -and $_.CommandLine -match $repoPattern
    })
}

New-Item -ItemType Directory -Force -Path $WorkDir,$SourceDir | Out-Null

if ($StatusOnly) {
    if (Test-Path -LiteralPath $StatePath) { Get-Content -Raw -LiteralPath $StatePath; exit 0 }
    Write-State "STATUS" "NO_PRIOR_STATE" $null "No previous parent download state was recorded."
    Get-Content -Raw -LiteralPath $StatePath
    exit 0
}

$existing = Get-SnapshotStatus $SourceDir
if ($existing.complete) {
    Write-State "PARENT_SNAPSHOT" "VERIFIED_COMPLETE" $null "Existing parent snapshot is complete; no network download required."
    Write-Host "BLACK 7.27 parent snapshot already VERIFIED COMPLETE" -ForegroundColor Green
    Write-Host "State: $StatePath"
    exit 0
}

$active = Get-ActiveParentTransfers
if ($active.Count -gt 0) {
    $sourcePattern = [regex]::Escape($SourceDir)
    $matching = @($active | Where-Object { $_.CommandLine -match $sourcePattern })
    if ($matching.Count -eq 0) {
        $pids = ($active | ForEach-Object { $_.ProcessId }) -join ','
        Write-State "PARENT_SNAPSHOT" "OTHER_PARENT_TRANSFER_ACTIVE" ([int]$active[0].ProcessId) "Same pinned parent is downloading in another WorkDir: $pids"
        throw "Pinned parent is already downloading in another Windows process/WorkDir: $pids. Refusing a duplicate large transfer."
    }

    $attachedPid = [int]$matching[0].ProcessId
    Write-Host "==> Attaching to existing Windows HF parent transfer PID $attachedPid" -ForegroundColor Yellow
    while ($true) {
        $live = Get-CimInstance Win32_Process -Filter "ProcessId = $attachedPid" -ErrorAction SilentlyContinue
        if (-not $live) { break }
        if (-not $live.CommandLine -or $live.CommandLine -notmatch [regex]::Escape([string]$Lock.uncensored_parent.repo)) { break }
        Write-State "PARENT_SNAPSHOT" "DOWNLOADING" $attachedPid "Attached to an existing Windows hf.exe transfer; no duplicate process was started."
        $bytes = Get-DirectoryBytes $SourceDir
        Write-Host ("[7.27] attached pid={0} parent={1:N2} GiB latest={2}" -f $attachedPid,($bytes/1GB),(Get-LatestWrite $SourceDir))
        Start-Sleep -Seconds $PollSeconds
    }

    $afterAttach = Get-SnapshotStatus $SourceDir
    if ($afterAttach.complete) {
        Write-State "PARENT_SNAPSHOT" "VERIFIED_COMPLETE" $null "Attached transfer ended with a complete pinned parent snapshot."
        Write-Host "BLACK 7.27 attached parent transfer VERIFIED COMPLETE" -ForegroundColor Green
        exit 0
    }

    Write-State "PARENT_SNAPSHOT" "RESUME_REQUIRED" $null "Attached hf.exe ended before snapshot completeness; existing partial files are preserved and will be resumed."
    Write-Host "[7.27] attached transfer ended incomplete; resuming the same SourceDir without purge." -ForegroundColor Yellow
}

$Python = Require-Command "python.exe"
if (-not (Test-Path -LiteralPath (Join-Path $VenvDir "Scripts\python.exe"))) {
    Write-State "TOOLING" "CREATING_VENV" $null "Creating reusable build venv."
    & $Python -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { throw "create build venv failed with exit code $LASTEXITCODE" }
}
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$Hf = Join-Path $VenvDir "Scripts\hf.exe"
if (-not (Test-Path -LiteralPath $Hf)) {
    Write-State "TOOLING" "INSTALLING_HF_XET" $null "Installing huggingface_hub[hf_xet] into reusable build venv."
    & $VenvPython -m pip install --disable-pip-version-check --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed with exit code $LASTEXITCODE" }
    & $VenvPython -m pip install --disable-pip-version-check "huggingface_hub[hf_xet]"
    if ($LASTEXITCODE -ne 0) { throw "huggingface_hub[hf_xet] install failed with exit code $LASTEXITCODE" }
}
if (-not (Test-Path -LiteralPath $Hf)) { throw "hf.exe was not created in the build venv: $Hf" }

$root = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $WorkDir).Path)
$drive = [IO.DriveInfo]::new($root)
$reusable = Get-DirectoryBytes $SourceDir
$effective = [int64]$drive.AvailableFreeSpace + [int64]$reusable
if ($effective -lt 125000000000L) {
    Write-State "PREFLIGHT" "BLOCKED_DISK" $null "Effective capacity is below the canonical 125,000,000,000 byte gate."
    throw "Parent preload blocked: effective capacity $effective bytes is below 125000000000 bytes. Existing partial data was preserved."
}

$previousXet = $env:HF_XET_HIGH_PERFORMANCE
$previousTimeout = $env:HF_HUB_DOWNLOAD_TIMEOUT
$env:HF_XET_HIGH_PERFORMANCE = "1"
$env:HF_HUB_DOWNLOAD_TIMEOUT = "600"
try {
    Write-State "PARENT_SNAPSHOT" "STARTING" $null "Starting resumable pinned parent download through Windows hf.exe / HF Xet."
    $args = @("download",[string]$Lock.uncensored_parent.repo,"--revision",[string]$Lock.uncensored_parent.revision,"--local-dir",$SourceDir)
    $process = Start-Process -FilePath $Hf -ArgumentList $args -WorkingDirectory $env:SystemRoot -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    while (-not $process.HasExited) {
        Write-State "PARENT_SNAPSHOT" "DOWNLOADING" ([int]$process.Id) "Windows hf.exe is active. A replacement CLI can rerun this script and attach instead of starting a duplicate."
        $bytes = Get-DirectoryBytes $SourceDir
        Write-Host ("[7.27] downloading pid={0} parent={1:N2} GiB latest={2}" -f $process.Id,($bytes/1GB),(Get-LatestWrite $SourceDir))
        Start-Sleep -Seconds $PollSeconds
        $process.Refresh()
    }
    if ($process.ExitCode -ne 0) {
        $detail = if (Test-Path -LiteralPath $StderrPath) { ((Get-Content -Tail 40 -LiteralPath $StderrPath -ErrorAction SilentlyContinue) -join "`n").Trim() } else { "" }
        Write-State "PARENT_SNAPSHOT" "FAILED" ([int]$process.Id) "hf.exe exit=$($process.ExitCode) $detail"
        throw "Pinned parent download failed with exit code $($process.ExitCode). Partial files were preserved for resume. $detail"
    }
    Assert-SnapshotComplete $SourceDir
    Write-State "PARENT_SNAPSHOT" "VERIFIED_COMPLETE" ([int]$process.Id) "All indexed safetensor shards are present and non-empty. Parent snapshot is ready for build reuse."
    Write-Host "BLACK 7.27 parent snapshot VERIFIED COMPLETE" -ForegroundColor Green
    Write-Host "Parent: $SourceDir"
    Write-Host "State:  $StatePath"
} finally {
    if ($null -eq $previousXet) { Remove-Item Env:HF_XET_HIGH_PERFORMANCE -ErrorAction SilentlyContinue } else { $env:HF_XET_HIGH_PERFORMANCE = $previousXet }
    if ($null -eq $previousTimeout) { Remove-Item Env:HF_HUB_DOWNLOAD_TIMEOUT -ErrorAction SilentlyContinue } else { $env:HF_HUB_DOWNLOAD_TIMEOUT = $previousTimeout }
}
