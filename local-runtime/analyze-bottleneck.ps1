param(
    [Parameter(Mandatory=$true)][string]$TelemetryPath,
    [Parameter(Mandatory=$true)][string]$LlamaStderr,
    [Parameter(Mandatory=$true)][int64]$StartupMs,
    [Parameter(Mandatory=$true)][int64]$TotalMs,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Sum-Field([object[]]$Rows, [string]$Kind) {
    $values = @($Rows | Where-Object { $_.kind -eq $Kind -and $_.measured -eq $true -and $null -ne $_.duration_ms } | ForEach-Object { [double]$_.duration_ms })
    if ($values.Count -eq 0) { return $null }
    return [Math]::Round(($values | Measure-Object -Sum).Sum)
}

$toolRows = @()
if (Test-Path -LiteralPath $TelemetryPath) {
    foreach ($line in Get-Content -LiteralPath $TelemetryPath -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $toolRows += ($line | ConvertFrom-Json) } catch {}
    }
}

$toolMs = Sum-Field $toolRows "tool"
$verifyMs = Sum-Field $toolRows "verify"
$toolCount = @($toolRows | Where-Object { $_.kind -eq "tool" }).Count
$verifyCount = @($toolRows | Where-Object { $_.kind -eq "verify" }).Count

$promptMs = 0.0
$decodeMs = 0.0
$promptMatches = 0
$decodeMatches = 0
if (Test-Path -LiteralPath $LlamaStderr) {
    foreach ($line in Get-Content -LiteralPath $LlamaStderr -ErrorAction SilentlyContinue) {
        if ($line -match 'prompt eval time\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*ms') { $promptMs += [double]$Matches[1]; $promptMatches++ }
        elseif ($line -match 'prompt_ms[^0-9]*([0-9]+(?:\.[0-9]+)?)') { $promptMs += [double]$Matches[1]; $promptMatches++ }
        if ($line -match '(?<!prompt )eval time\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*ms') { $decodeMs += [double]$Matches[1]; $decodeMatches++ }
        elseif ($line -match 'predicted_ms[^0-9]*([0-9]+(?:\.[0-9]+)?)') { $decodeMs += [double]$Matches[1]; $decodeMatches++ }
    }
}

$modelPromptMs = if ($promptMatches -gt 0) { [Math]::Round($promptMs) } else { $null }
$modelDecodeMs = if ($decodeMatches -gt 0) { [Math]::Round($decodeMs) } else { $null }
$modelMs = if ($null -ne $modelPromptMs -or $null -ne $modelDecodeMs) { [Math]::Round(([double]($modelPromptMs ?? 0)) + ([double]($modelDecodeMs ?? 0))) } else { $null }

$measuredParts = @{
    startup = [double]$StartupMs
    model = if ($null -ne $modelMs) { [double]$modelMs } else { 0.0 }
    tool = if ($null -ne $toolMs) { [double]$toolMs } else { 0.0 }
    verify = if ($null -ne $verifyMs) { [double]$verifyMs } else { 0.0 }
}
$knownMs = ($measuredParts.Values | Measure-Object -Sum).Sum
$unattributedMs = [Math]::Max(0, $TotalMs - $knownMs)

$candidates = @()
foreach ($name in @("startup","model","tool","verify")) {
    $value = $measuredParts[$name]
    if ($value -gt 0) { $candidates += [pscustomobject]@{ name=$name; value=$value } }
}
$largest = $candidates | Sort-Object value -Descending | Select-Object -First 1
$bottleneck = if ($largest) { $largest.name } else { "UNKNOWN" }

$record = [ordered]@{
    schema_version = "1.0"
    recorded_at = (Get-Date).ToString("o")
    total_ms = $TotalMs
    startup_ms = $StartupMs
    model = [ordered]@{
        total_ms = $modelMs
        prompt_ms = $modelPromptMs
        decode_ms = $modelDecodeMs
        timing_samples = [Math]::Max($promptMatches, $decodeMatches)
        status = if ($null -ne $modelMs) { "MEASURED" } else { "UNKNOWN" }
    }
    tool = [ordered]@{ total_ms = $toolMs; count = $toolCount; status = if ($null -ne $toolMs) { "MEASURED" } else { "UNKNOWN" } }
    verify = [ordered]@{ total_ms = $verifyMs; count = $verifyCount; status = if ($null -ne $verifyMs) { "MEASURED" } else { "UNKNOWN" } }
    unattributed_ms = [Math]::Round($unattributedMs)
    largest_measured_bottleneck = $bottleneck
    recommendation = switch ($bottleneck) {
        "model" { "Reduce prompt/model work before changing tool execution." }
        "tool" { "Reduce or batch non-verification tool calls." }
        "verify" { "Tighten affected-test selection before broad verification." }
        "startup" { "Optimize runtime startup/model load path." }
        default { "Collect more timing evidence before changing the runtime." }
    }
    safety = "OBSERVATION_ONLY"
}

$dir = Split-Path -Parent $OutputPath
if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$record | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $OutputPath
$record | ConvertTo-Json -Depth 8 -Compress | Add-Content -Encoding UTF8 -LiteralPath (Join-Path $dir "bottlenecks.jsonl")
Write-Host ("Bottleneck: {0} | startup={1}ms model={2} tool={3} verify={4} unattributed={5}ms" -f $bottleneck,$StartupMs,$modelMs,$toolMs,$verifyMs,[Math]::Round($unattributedMs))
