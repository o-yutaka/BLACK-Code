Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RuntimeRoot = $PSScriptRoot

function Assert-Contains([string]$Path, [string[]]$Needles) {
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($needle in $Needles) { if (-not $content.Contains($needle)) { throw "Missing contract '$needle' in $Path" } }
}
function Assert-NotContains([string]$Path, [string[]]$Needles) {
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($needle in $Needles) { if ($content.Contains($needle)) { throw "Rejected runtime contract '$needle' is present in $Path" } }
}

$files = @(
    (Join-Path $RuntimeRoot "black-code.ps1"),
    (Join-Path $RuntimeRoot "setup.ps1"),
    (Join-Path $RuntimeRoot "doctor.ps1"),
    (Join-Path $RuntimeRoot "execution-fabric.ps1"),
    (Join-Path $RuntimeRoot "repo-index.ps1"),
    (Join-Path $RuntimeRoot "analyze-bottleneck.ps1"),
    (Join-Path $RuntimeRoot "verify.ps1")
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Required runtime file is missing: $file" }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "PowerShell parse failed: $file :: $($parseErrors[0].Message)" }
}

$launcher = Join-Path $RuntimeRoot "black-code.ps1"
Assert-Contains $launcher @(
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf','Get-BlackCodeRepoIndex','instructions = @("black-code-execution.md", "repo-context.md")',
    '$Context = 8192','$Context = 12288','$Context = 16384','"--spec-type","draft-mtp"','"--spec-draft-n-max","2"',
    '$env:BLACK_CODE_TELEMETRY_PATH = $telemetryPath','analyze-bottleneck.ps1','observation-only auto bottleneck','Write-BlackCodeSessionEvidence'
)
Assert-NotContains $launcher @('$ModelFile = "Qwen3.8-27B-Uncensored-IQ4_XS.gguf"','draft-mtp,ngram-mod','"--cache-reuse"','"--tensor-split"','"-ts"')

$index = Join-Path $RuntimeRoot "repo-index.ps1"
Assert-Contains $index @('cache_status = "HIT"','"DELTA_REFRESH"','"MISS_BUILD"','diff --name-only','package_roots','likely_tests','repo-context.md')

$telemetry = Join-Path $RuntimeRoot "opencode-telemetry.js"
if (-not (Test-Path -LiteralPath $telemetry)) { throw "Required telemetry plugin missing" }
Assert-Contains $telemetry @('tool.execute.before','tool.execute.after','BLACK_CODE_TELEMETRY_PATH','kind: classify','duration_ms','measured: Boolean(start)')
Assert-NotContains $telemetry @('command: start?.command','slice(0, 500)')

$analyzer = Join-Path $RuntimeRoot "analyze-bottleneck.ps1"
Assert-Contains $analyzer @('OBSERVATION_ONLY','largest_measured_bottleneck','unattributed_ms','prompt eval time','predicted_ms','"UNKNOWN"')

$setup = Join-Path $RuntimeRoot "setup.ps1"
Assert-Contains $setup @('$ModelFile = "Qwen3.8-27B-Uncensored-IQ2_M.gguf"','28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187','"repo-index.ps1"','"analyze-bottleneck.ps1"','"opencode-telemetry.js"','.config\opencode\plugins','black-code-telemetry.js','bottleneck_analyzer="observation-only-v1"','mtp_draft_max=2')

$doctor = Join-Path $RuntimeRoot "doctor.ps1"
Assert-Contains $doctor @('Qwen3.8-27B-Uncensored-IQ2_M.gguf','28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187','IQ2_M HASH VERIFIED')

$temp = Join-Path ([IO.Path]::GetTempPath()) ("black-code-verify-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    # Execute the OpenCode hook shape with Node as an ESM smoke test.
    $node = (Get-Command node -ErrorAction Stop).Source
    $pluginMjs = Join-Path $temp "opencode-telemetry.mjs"
    Copy-Item -Force $telemetry $pluginMjs
    $hookLog = Join-Path $temp "hook-tools.jsonl"
    $smokeMjs = Join-Path $temp "smoke.mjs"
    @'
import { pathToFileURL } from "node:url"
const [pluginPath, logPath] = process.argv.slice(2)
process.env.BLACK_CODE_TELEMETRY_PATH = logPath
const mod = await import(pathToFileURL(pluginPath).href)
const hooks = await mod.BlackCodeTelemetry()
const input = { tool: "bash", sessionID: "session-smoke", callID: "call-smoke" }
const output = { args: { command: "pnpm test" } }
await hooks["tool.execute.before"](input, output)
await new Promise((resolve) => setTimeout(resolve, 15))
await hooks["tool.execute.after"](input, {})
'@ | Set-Content -Encoding UTF8 $smokeMjs
    & $node $smokeMjs $pluginMjs $hookLog
    if ($LASTEXITCODE -ne 0) { throw "Telemetry Node smoke failed with exit code $LASTEXITCODE" }
    $hookRow = (Get-Content -LiteralPath $hookLog | Select-Object -First 1) | ConvertFrom-Json
    if ($hookRow.kind -ne "verify") { throw "Telemetry hook failed to classify verification" }
    if ($hookRow.measured -ne $true -or $hookRow.duration_ms -lt 0) { throw "Telemetry hook did not emit measured timing" }
    if ($hookRow.PSObject.Properties.Name -contains "command") { throw "Telemetry unexpectedly persisted command content" }

    # Synthetic analyzer test proves Windows PowerShell decomposition.
    $toolLog = Join-Path $temp "tools.jsonl"
    @('{"kind":"tool","duration_ms":250,"measured":true}','{"kind":"verify","duration_ms":700,"measured":true}') | Set-Content -Encoding UTF8 $toolLog
    $llamaLog = Join-Path $temp "llama.err"
    @('prompt eval time = 300.00 ms / 10 tokens','eval time = 900.00 ms / 20 runs') | Set-Content -Encoding UTF8 $llamaLog
    $out = Join-Path $temp "result.json"
    & $analyzer -TelemetryPath $toolLog -LlamaStderr $llamaLog -StartupMs 100 -TotalMs 3000 -OutputPath $out | Out-Null
    $result = Get-Content -Raw -LiteralPath $out | ConvertFrom-Json
    if ($result.model.total_ms -ne 1200) { throw "Synthetic model timing mismatch" }
    if ($result.tool.total_ms -ne 250) { throw "Synthetic tool timing mismatch" }
    if ($result.verify.total_ms -ne 700) { throw "Synthetic verify timing mismatch" }
    if ($result.largest_measured_bottleneck -ne "model") { throw "Synthetic bottleneck classification mismatch" }
    if ($result.safety -ne "OBSERVATION_ONLY") { throw "Analyzer safety contract mismatch" }
}
finally { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $temp }

Write-Host "BLACK CODE AUTO BOTTLENECK OBSERVABILITY HOOK+ANALYZER VERIFY: PASS" -ForegroundColor Green
