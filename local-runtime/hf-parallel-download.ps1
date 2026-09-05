param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Destination,
    [ValidateRange(1, 16)][int]$Workers = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:LASTEXITCODE = 0

function Resolve-Curl {
    $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if (-not $curl) { $curl = Get-Command "curl" -ErrorAction SilentlyContinue }
    if (-not $curl) { throw "curl was not found." }
    return $curl.Source
}

function Download-Sequential([string]$Curl, [string]$Source, [string]$Target) {
    $partial = "$Target.part"
    $args = @("-L", "--fail", "--retry", "8", "--retry-all-errors", "--retry-delay", "2", "-o", $partial, $Source)
    if (Test-Path -LiteralPath $partial) { $args = @("-C", "-") + $args }
    Write-Host "HF parallel range download unavailable; using resumable single-stream fallback." -ForegroundColor Yellow
    & $Curl @args
    if ($LASTEXITCODE -ne 0) { throw "Sequential curl download failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $partial)) { throw "Sequential download produced no file: $partial" }
    Move-Item -Force -LiteralPath $partial -Destination $Target
}

$curl = Resolve-Curl
$destinationDirectory = Split-Path -Parent $Destination
if (-not $destinationDirectory) { $destinationDirectory = (Get-Location).Path }
New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

$partial = "$Destination.part"
$chunkRoot = "$partial.chunks"
$probeHeaders = "$partial.probe.headers"
$probeBody = "$partial.probe.body"
Remove-Item -Force -ErrorAction SilentlyContinue $probeHeaders, $probeBody

Write-Host "HF download probe: $Url"
& $curl -L --fail --silent --show-error --retry 3 --range "0-0" --dump-header $probeHeaders --output $probeBody $Url
$probeCode = $LASTEXITCODE
$totalBytes = $null
if ($probeCode -eq 0 -and (Test-Path -LiteralPath $probeHeaders)) {
    foreach ($line in Get-Content -LiteralPath $probeHeaders) {
        if ($line -match '^(?i)Content-Range:\s*bytes\s+0-0/(\d+)') { $totalBytes = [int64]$Matches[1] }
    }
}
Remove-Item -Force -ErrorAction SilentlyContinue $probeHeaders, $probeBody

if ($null -eq $totalBytes -or $totalBytes -le 1 -or $Workers -le 1) {
    Download-Sequential $curl $Url $Destination
    return
}

$actualWorkers = [Math]::Min($Workers, [int][Math]::Ceiling($totalBytes / 67108864.0))
$actualWorkers = [Math]::Max(1, $actualWorkers)
if ($actualWorkers -le 1) {
    Download-Sequential $curl $Url $Destination
    return
}

New-Item -ItemType Directory -Force -Path $chunkRoot | Out-Null
$chunkSize = [int64][Math]::Ceiling($totalBytes / [double]$actualWorkers)
$jobs = New-Object System.Collections.Generic.List[object]
$chunks = New-Object System.Collections.Generic.List[object]

Write-Host "HF parallel download: $actualWorkers workers / $([Math]::Round($totalBytes / 1GB, 2)) GiB" -ForegroundColor Green
for ($index = 0; $index -lt $actualWorkers; $index++) {
    $start = [int64]$index * $chunkSize
    if ($start -ge $totalBytes) { break }
    $end = [Math]::Min($totalBytes - 1, $start + $chunkSize - 1)
    $expected = [int64]($end - $start + 1)
    $chunk = Join-Path $chunkRoot ("chunk-{0:D2}.part" -f $index)
    $stderr = Join-Path $chunkRoot ("chunk-{0:D2}.err" -f $index)
    [void]$chunks.Add([PSCustomObject]@{ index = $index; start = $start; end = $end; expected = $expected; path = $chunk; stderr = $stderr })

    if ((Test-Path -LiteralPath $chunk) -and (Get-Item -LiteralPath $chunk).Length -eq $expected) {
        Write-Host ("  chunk {0:D2}: cached" -f $index)
        continue
    }
    Remove-Item -Force -ErrorAction SilentlyContinue $chunk, $stderr
    $args = @(
        "-L", "--fail", "--silent", "--show-error",
        "--retry", "8", "--retry-all-errors", "--retry-delay", "2",
        "--range", "$start-$end", "--output", $chunk, $Url
    )
    $process = Start-Process -FilePath $curl -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardError $stderr
    [void]$jobs.Add([PSCustomObject]@{ process = $process; chunk = $chunk; stderr = $stderr; expected = $expected; index = $index })
}

$failed = $false
foreach ($job in $jobs) {
    $job.process.WaitForExit()
    $size = if (Test-Path -LiteralPath $job.chunk) { (Get-Item -LiteralPath $job.chunk).Length } else { -1 }
    if ($job.process.ExitCode -ne 0 -or $size -ne $job.expected) {
        $failed = $true
        $detail = if (Test-Path -LiteralPath $job.stderr) { (Get-Content -Raw -LiteralPath $job.stderr -ErrorAction SilentlyContinue).Trim() } else { "" }
        Write-Warning ("HF chunk {0:D2} failed: exit={1} bytes={2}/{3} {4}" -f $job.index, $job.process.ExitCode, $size, $job.expected, $detail)
    }
    else { Write-Host ("  chunk {0:D2}: ok ({1:N0} MiB)" -f $job.index, ($size / 1MB)) }
}

if ($failed) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $chunkRoot
    Download-Sequential $curl $Url $Destination
    return
}

$out = [System.IO.File]::Open($partial, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try {
    foreach ($chunkInfo in $chunks | Sort-Object index) {
        $input = [System.IO.File]::OpenRead($chunkInfo.path)
        try { $input.CopyTo($out) }
        finally { $input.Dispose() }
    }
}
finally { $out.Dispose() }

$combinedBytes = (Get-Item -LiteralPath $partial).Length
if ($combinedBytes -ne $totalBytes) {
    throw "Parallel HF combine size mismatch: $combinedBytes / $totalBytes bytes"
}
Move-Item -Force -LiteralPath $partial -Destination $Destination
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $chunkRoot
Write-Host "HF parallel download complete: $Destination" -ForegroundColor Green
