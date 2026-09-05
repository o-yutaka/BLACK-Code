Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0

$RuntimeRoot = $PSScriptRoot

function Assert-Contains([string]$Path, [string[]]$Needles) {
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($needle in $Needles) { if (-not $content.Contains($needle)) { throw "Missing contract '$needle' in $Path" } }
}
function Assert-NotContains([string]$Path, [string[]]$Needles) {
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($needle in $Needles) { if ($content.Contains($needle)) { throw "Rejected runtime contract '$needle' is present in $Path" } }
}

$powerShellFiles = @(
    "black-code.ps1",
    "setup.ps1",
    "doctor.ps1",
    "execution-fabric.ps1",
    "repo-index.ps1",
    "rule-bridge.ps1",
    "verification-gate.ps1",
    "hf-parallel-download.ps1",
    "analyze-bottleneck.ps1",
    "verify.ps1"
) | ForEach-Object { Join-Path $RuntimeRoot $_ }
foreach ($file in $powerShellFiles) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Required runtime file is missing: $file" }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "PowerShell parse failed: $file :: $($parseErrors[0].Message)" }
}

$launcher = Join-Path $RuntimeRoot "black-code.ps1"
Assert-Contains $launcher @(
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf',
    'Get-BlackCodeRepoIndex',
    'instructions = @("black-code-execution.md", "repo-context.md", "project-rules.md")',
    'plugin = @($telemetryPluginUri, $governorPluginUri)',
    'rule-bridge.ps1',
    'BLACK_CODE_GOVERNOR_DIR',
    'BLACK_CODE_PROJECT_ROOT',
    'BLACK_CODE_VERIFY_SCRIPT',
    '$Context = 8192','$Context = 12288','$Context = 16384',
    '"--spec-type","draft-mtp"','"--spec-draft-n-max","2"',
    '"--parallel","1"',
    'Vision:    OFF / no sidecar',
    '$env:BLACK_CODE_TELEMETRY_PATH = $telemetryPath',
    'analyze-bottleneck.ps1',
    'Write-BlackCodeSessionEvidence'
)
Assert-NotContains $launcher @('$ModelFile = "Qwen3.8-27B-Uncensored-IQ4_XS.gguf"','draft-mtp,ngram-mod','"--cache-reuse"','"--tensor-split"','"-ts"')

$index = Join-Path $RuntimeRoot "repo-index.ps1"
Assert-Contains $index @('cache_status = "HIT"','"DELTA_REFRESH"','"MISS_BUILD"','diff --name-only','package_roots','likely_tests','repo-context.md')

$fabric = Join-Path $RuntimeRoot "execution-fabric.ps1"
Assert-Contains $fabric @('black-execution-fabric-governed-v2','verify.hash-bound-final','continuity.unverified-state','local_parallel_slots = 1','vision = $false','candidate_7_27gb_status = "not_promoted_until_built_and_verified"')

$instructions = Join-Path $RuntimeRoot "black-code-execution.md"
Assert-Contains $instructions @('WORKSPACE IS AUTHORITY','STRUCTURAL_OK','FINAL VERIFY','black-code-verify','HASH-BOUND COMPLETION','TEXT/CODE ONLY','INDEX -> RULES -> DELTA -> BATCH -> EDIT')

$telemetry = Join-Path $RuntimeRoot "opencode-telemetry.js"
$governor = Join-Path $RuntimeRoot "opencode-governor.js"
foreach ($plugin in @($telemetry, $governor)) { if (-not (Test-Path -LiteralPath $plugin)) { throw "Required OpenCode plugin missing: $plugin" } }
Assert-Contains $telemetry @('tool.execute.before','tool.execute.after','BLACK_CODE_TELEMETRY_PATH','kind: classify','duration_ms','measured: Boolean(start)')
Assert-NotContains $telemetry @('command: start?.command','slice(0, 500)')
Assert-Contains $governor @('workspaceFingerprint','BLACK_CODE_GOVERNOR_DIR','BLACK_CODE_PROJECT_ROOT','apply_patch','black-code-verify','experimental.text.complete','BLACK VERIFY: UNVERIFIED','repeat guard','verification_token')

$analyzer = Join-Path $RuntimeRoot "analyze-bottleneck.ps1"
Assert-Contains $analyzer @('OBSERVATION_ONLY','largest_measured_bottleneck','unattributed_ms','prompt eval time','predicted_ms','"UNKNOWN"')

$setup = Join-Path $RuntimeRoot "setup.ps1"
Assert-Contains $setup @(
    '$ModelFile = "Qwen3.8-27B-Uncensored-IQ2_M.gguf"',
    '28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187',
    '[ValidateRange(1, 16)][int]$HfDownloadWorkers = 8',
    'hf-parallel-download.ps1',
    '-Workers $HfDownloadWorkers',
    'opencode-governor.js',
    'verification-gate.ps1',
    'rule-bridge.ps1',
    'black-code-verify.cmd',
    'custom_7_27gb_candidate="not-installed-until-built-and-verified"',
    'local_parallel_slots=1',
    'vision=$false',
    'mtp_draft_max=2'
)

$hfDownloader = Join-Path $RuntimeRoot "hf-parallel-download.ps1"
Assert-Contains $hfDownloader @('Content-Range','Start-Process','--range','chunk-{0:D2}.part','HF parallel download','Download-Sequential')
Assert-NotContains $hfDownloader @('exit 0')

$ruleBridge = Join-Path $RuntimeRoot "rule-bridge.ps1"
Assert-Contains $ruleBridge @('.claude\CLAUDE.md','CLAUDE.local.md','BLACK.md','@([^\s`]+)','Depth -gt 5','24000')

$finalGate = Join-Path $RuntimeRoot "verification-gate.ps1"
Assert-Contains $finalGate @('git-diff-check','node-verify','python-pytest','cargo-test','go-test','dotnet-test','RuntimeCommand','BLACK_CODE_VERIFY=PASS','no-strong-project-or-runtime-check')

$doctor = Join-Path $RuntimeRoot "doctor.ps1"
Assert-Contains $doctor @('Qwen3.8-27B-Uncensored-IQ2_M.gguf','28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187','IQ2_M HASH VERIFIED')

$temp = Join-Path ([IO.Path]::GetTempPath()) ("black-code-verify-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCommand) { $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue }
    if (-not $nodeCommand) { throw "Node.js was not found in PATH." }
    $node = $nodeCommand.Source

    # Telemetry hook execution smoke.
    $pluginMjs = Join-Path $temp "opencode-telemetry.mjs"
    Copy-Item -Force $telemetry $pluginMjs
    $hookLog = Join-Path $temp "hook-tools.jsonl"
    $smokeMjs = Join-Path $temp "telemetry-smoke.mjs"
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
    $nodeStdout = Join-Path $temp "telemetry.stdout"
    $nodeStderr = Join-Path $temp "telemetry.stderr"
    $nodeProcess = Start-Process -FilePath $node -ArgumentList @($smokeMjs, $pluginMjs, $hookLog) -Wait -PassThru -RedirectStandardOutput $nodeStdout -RedirectStandardError $nodeStderr
    if ($nodeProcess.ExitCode -ne 0) { $detail=(Get-Content -Raw -Path $nodeStderr -ErrorAction SilentlyContinue).Trim(); throw "Telemetry Node smoke failed with exit code $($nodeProcess.ExitCode): $detail" }
    if (-not (Test-Path -LiteralPath $hookLog)) { throw "Telemetry Node smoke produced no hook log." }
    $hookRow = (Get-Content -LiteralPath $hookLog | Select-Object -First 1) | ConvertFrom-Json
    if ($hookRow.kind -ne "verify") { throw "Telemetry hook failed to classify verification" }
    if ($hookRow.measured -ne $true -or $hookRow.duration_ms -lt 0) { throw "Telemetry hook did not emit measured timing" }
    if ($hookRow.PSObject.Properties.Name -contains "command") { throw "Telemetry unexpectedly persisted command content" }

    # Completion governor smoke: dirty -> blocked; verify -> allowed; later edit -> blocked; identical failed retry -> rejected.
    $governorMjs = Join-Path $temp "opencode-governor.mjs"
    Copy-Item -Force $governor $governorMjs
    $govProject = Join-Path $temp "governor-project"
    $govState = Join-Path $temp "governor-state"
    New-Item -ItemType Directory -Force -Path $govProject,$govState | Out-Null
    Set-Content -Encoding UTF8 (Join-Path $govProject "state.txt") "initial"
    $govSmoke = Join-Path $temp "governor-smoke.mjs"
    @'
import fs from "node:fs"
import path from "node:path"
import { pathToFileURL } from "node:url"
const [pluginPath, project, stateDir] = process.argv.slice(2)
process.env.BLACK_CODE_PROJECT_ROOT = project
process.env.BLACK_CODE_GOVERNOR_DIR = stateDir
const mod = await import(pathToFileURL(pluginPath).href)
const hooks = await mod.BlackCodeGovernor({ directory: project, worktree: project })
const edit = { tool: "write", sessionID: "gov-session", callID: "edit-1" }
await hooks["tool.execute.before"](edit, { args: { filePath: path.join(project, "state.txt") } })
fs.writeFileSync(path.join(project, "state.txt"), "changed\n")
await hooks["tool.execute.after"](edit, { title: "write", output: "", metadata: {} })
const first = { text: "COMPLETE" }
await hooks["experimental.text.complete"]({ sessionID: "gov-session", messageID: "m1", partID: "p1" }, first)
if (!first.text.includes("BLACK VERIFY: UNVERIFIED")) throw new Error("dirty completion was not blocked")
const verify = { tool: "bash", sessionID: "gov-session", callID: "verify-1" }
await hooks["tool.execute.before"](verify, { args: { command: "black-code-verify" } })
await hooks["tool.execute.after"](verify, { title: "verify", output: "PASS", metadata: { exitCode: 0 } })
const second = { text: "COMPLETE" }
await hooks["experimental.text.complete"]({ sessionID: "gov-session", messageID: "m2", partID: "p2" }, second)
if (second.text !== "COMPLETE") throw new Error("verified completion was unexpectedly blocked")
fs.appendFileSync(path.join(project, "state.txt"), "later edit\n")
const third = { text: "COMPLETE" }
await hooks["experimental.text.complete"]({ sessionID: "gov-session", messageID: "m3", partID: "p3" }, third)
if (!third.text.includes("BLACK VERIFY: UNVERIFIED")) throw new Error("post-verify mutation did not invalidate token")
const fail = { tool: "bash", sessionID: "gov-session", callID: "fail-1" }
await hooks["tool.execute.before"](fail, { args: { command: "node -e process.exit(1)" } })
await hooks["tool.execute.after"](fail, { title: "fail", output: "", metadata: { exitCode: 1 } })
let guarded = false
try {
  await hooks["tool.execute.before"]({ tool: "bash", sessionID: "gov-session", callID: "fail-2" }, { args: { command: "node -e process.exit(1)" } })
} catch { guarded = true }
if (!guarded) throw new Error("identical failed retry was not blocked")
'@ | Set-Content -Encoding UTF8 $govSmoke
    $govStdout = Join-Path $temp "governor.stdout"
    $govStderr = Join-Path $temp "governor.stderr"
    $govProcess = Start-Process -FilePath $node -ArgumentList @($govSmoke, $governorMjs, $govProject, $govState) -Wait -PassThru -RedirectStandardOutput $govStdout -RedirectStandardError $govStderr
    if ($govProcess.ExitCode -ne 0) { $detail=(Get-Content -Raw -Path $govStderr -ErrorAction SilentlyContinue).Trim(); throw "Governor Node smoke failed with exit code $($govProcess.ExitCode): $detail" }

    # Rule bridge smoke including non-fenced @file import.
    $ruleProject = Join-Path $temp "rule-project"
    New-Item -ItemType Directory -Force -Path $ruleProject | Out-Null
    Set-Content -Encoding UTF8 (Join-Path $ruleProject "CLAUDE.md") "root-rule`n@extra.md"
    Set-Content -Encoding UTF8 (Join-Path $ruleProject "extra.md") "imported-rule"
    Set-Content -Encoding UTF8 (Join-Path $ruleProject "BLACK.md") "black-rule"
    $ruleOut = Join-Path $temp "project-rules.md"
    & $ruleBridge -ProjectRoot $ruleProject -Destination $ruleOut | Out-Null
    $ruleText = Get-Content -Raw -LiteralPath $ruleOut
    foreach ($needle in @("root-rule","imported-rule","black-rule")) { if (-not $ruleText.Contains($needle)) { throw "Rule bridge smoke missing $needle" } }

    # Final verification gate smoke in a synthetic Node project.
    $gateProject = Join-Path $temp "gate-project"
    New-Item -ItemType Directory -Force -Path $gateProject | Out-Null
    '{"scripts":{"verify":"node verify.js"}}' | Set-Content -Encoding UTF8 (Join-Path $gateProject "package.json")
    'process.exit(0)' | Set-Content -Encoding UTF8 (Join-Path $gateProject "verify.js")
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $gateStdout = Join-Path $temp "gate.stdout"
    $gateStderr = Join-Path $temp "gate.stderr"
    $gateProcess = Start-Process -FilePath $powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$finalGate,"-ProjectRoot",$gateProject) -Wait -PassThru -RedirectStandardOutput $gateStdout -RedirectStandardError $gateStderr
    if ($gateProcess.ExitCode -ne 0) { $detail=(Get-Content -Raw -Path $gateStderr -ErrorAction SilentlyContinue).Trim(); throw "Final verification gate smoke failed with exit code $($gateProcess.ExitCode): $detail" }
    if (-not (Get-Content -Raw -LiteralPath $gateStdout).Contains("BLACK_CODE_VERIFY=PASS")) { throw "Final verification gate did not emit PASS marker" }

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

Write-Host "BLACK CODE GOVERNED RUNTIME VERIFY: PASS" -ForegroundColor Green
