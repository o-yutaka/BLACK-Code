param(
    [string]$ModelWorkDir = (Join-Path $env:LOCALAPPDATA "BLACK-Code\model-build-7.27"),
    [ValidateRange(1,16)][int]$HfDownloadWorkers = 8,
    [ValidateRange(5,300)][int]$PollSeconds = 15,
    [switch]$TransferStatusOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0

if ($env:OS -ne "Windows_NT") { throw "BLACK Code resilient setup must run in Windows PowerShell." }

$Transfer = Join-Path $PSScriptRoot "download-parent-7.27.ps1"
$Setup = Join-Path $PSScriptRoot "setup.ps1"
foreach ($required in @($Transfer,$Setup)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required BLACK Code setup component missing: $required" }
}

if ($TransferStatusOnly) {
    & $Transfer -WorkDir $ModelWorkDir -PollSeconds $PollSeconds -StatusOnly
    exit $LASTEXITCODE
}

Write-Host ""; Write-Host "==> BLACK Code resilient parent transfer / handoff" -ForegroundColor Cyan
Write-Host "WorkDir: $ModelWorkDir"
& $Transfer -WorkDir $ModelWorkDir -PollSeconds $PollSeconds
if ($LASTEXITCODE -ne 0) { throw "Parent transfer layer failed with exit code $LASTEXITCODE" }

$statePath = Join-Path $ModelWorkDir "parent-download.state.json"
if (-not (Test-Path -LiteralPath $statePath)) { throw "Parent transfer completed without durable state: $statePath" }
$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if ([string]$state.status -ne "COMPLETE") { throw "Parent transfer is not complete: status=$($state.status)" }
if ([int64]$state.source_bytes -le 0) { throw "Parent transfer state reports zero source bytes." }

Write-Host ""; Write-Host "==> Parent snapshot is durable and complete; entering canonical setup" -ForegroundColor Cyan
& $Setup -ModelWorkDir $ModelWorkDir -HfDownloadWorkers $HfDownloadWorkers
if ($LASTEXITCODE -ne 0) { throw "Canonical BLACK Code setup failed with exit code $LASTEXITCODE" }
