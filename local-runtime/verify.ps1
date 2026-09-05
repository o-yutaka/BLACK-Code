Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0
$RuntimeRoot = $PSScriptRoot

function Assert-Contains([string]$Path,[string[]]$Needles) {
    $content=Get-Content -Raw -LiteralPath $Path
    foreach($needle in $Needles){if(-not $content.Contains($needle)){throw "Missing contract '$needle' in $Path"}}
}
function Assert-NotContains([string]$Path,[string[]]$Needles) {
    $content=Get-Content -Raw -LiteralPath $Path
    foreach($needle in $Needles){if($content.Contains($needle)){throw "Rejected contract '$needle' is present in $Path"}}
}

$requiredFiles=@(
    "black-code.ps1","setup.ps1","doctor.ps1","execution-fabric.ps1","repo-index.ps1","rule-bridge.ps1",
    "verification-gate.ps1","hf-parallel-download.ps1","build-model-7.27.ps1","extract-quant-map.mjs",
    "model-7.27.lock.json","MODEL_7_27GB.md","black-code-execution.md","analyze-bottleneck.ps1",
    "opencode-telemetry.js","opencode-governor.js","verify.ps1","CANONICAL_ARCHITECTURE.md","SPEED_PROFILE.md"
)
foreach($name in $requiredFiles){if(-not(Test-Path -LiteralPath (Join-Path $RuntimeRoot $name))){throw "Required runtime file missing: $name"}}
if(Test-Path -LiteralPath (Join-Path $RuntimeRoot "CANDIDATE_7_27GB.md")){throw "Obsolete CANDIDATE_7_27GB.md still exists"}

$powerShellFiles=@("black-code.ps1","setup.ps1","doctor.ps1","execution-fabric.ps1","repo-index.ps1","rule-bridge.ps1","verification-gate.ps1","hf-parallel-download.ps1","build-model-7.27.ps1","analyze-bottleneck.ps1","verify.ps1")|ForEach-Object{Join-Path $RuntimeRoot $_}
foreach($file in $powerShellFiles){
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){throw "PowerShell parse failed: $file :: $($parseErrors[0].Message)"}
}

$nodeCommand=Get-Command node -ErrorAction SilentlyContinue
if(-not $nodeCommand){$nodeCommand=Get-Command node.exe -ErrorAction SilentlyContinue}
if(-not $nodeCommand){throw "Node.js was not found in PATH."}
$node=$nodeCommand.Source
foreach($jsName in @("extract-quant-map.mjs","opencode-telemetry.js","opencode-governor.js")){
    & $node --check (Join-Path $RuntimeRoot $jsName)
    if($LASTEXITCODE -ne 0){throw "Node syntax check failed: $jsName"}
}

$lock=Get-Content -Raw -LiteralPath (Join-Path $RuntimeRoot "model-7.27.lock.json")|ConvertFrom-Json
if($lock.canonical_model.file -ne "Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf"){throw "canonical model lock filename mismatch"}
if($lock.canonical_model.alias -ne "qwen3.8-27b-uncensored-black-7.27"){throw "canonical model alias mismatch"}
if([int64]$lock.canonical_model.target_min_bytes -ne 7200000000L -or [int64]$lock.canonical_model.target_max_bytes -ne 7350000000L){throw "canonical size window changed"}
if($lock.canonical_model.no_mtp -ne $true -or $lock.canonical_model.vision -ne $false){throw "main model must be no-MTP and vision-free"}
if($lock.uncensored_parent.revision -ne "5bb7aa90f0efef548e87005b1fb7658e522b6b7f"){throw "uncensored parent revision changed"}
if($lock.quant_map_reference.sha256 -ne "e792d8fb3142fe6d9171876d6da0f71f05a71028718debc72dbec93ff645e67d"){throw "7.27 reference SHA changed"}
if($lock.imatrix.sha256 -ne "3e85d5a338133e9c975da92c009cf3bbcb42557fbafc45fc33c9dc3e537ba240"){throw "imatrix SHA changed"}
if($lock.mtp_draft.sha256 -ne "f3ac2acd205b2f9acc1b027b67867f4ba1cf84761d226024a3b153345a69e127"){throw "MTP draft SHA changed"}

$launcher=Join-Path $RuntimeRoot "black-code.ps1"
Assert-Contains $launcher @(
    'Qwen3.8-27B-Uncensored-BLACK-UD-IQ2_XXS.gguf','qwen3.8-27b-uncensored-black-7.27',
    'Qwen3.8-27B-Uncensored-draft-Q4_0.gguf','"--spec-draft-model",$DraftPath','"--spec-type","draft-mtp"','"--spec-draft-n-max","2"',
    '"--parallel","1"','model-7.27.local.json','CANONICAL_FIXED','Vision:    OFF / no sidecar',
    'Get-BlackCodeRepoIndex','opencode-governor.js','BLACK_CODE_GOVERNOR_DIR','analyze-bottleneck.ps1'
)
Assert-NotContains $launcher @('Qwen3.8-27B-Uncensored-IQ2_M.gguf','IQ2_M 10.6','custom_7_27gb_candidate')

$setup=Join-Path $RuntimeRoot "setup.ps1"
Assert-Contains $setup @(
    'model-7.27.lock.json','build-model-7.27.ps1','model-7.27.local.json','canonical-fixed',
    '[ValidateRange(1, 16)][int]$HfDownloadWorkers = 8','-HfDownloadWorkers $HfDownloadWorkers',
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf','Removed superseded model','MTP draft HASH VERIFIED',
    'hf-parallel-download.ps1','extract-quant-map.mjs','BLACK-UD-IQ2_XXS-exact-reference-map','external-draft-mtp'
)
Assert-NotContains $setup @('model_role="verified-baseline"','custom_7_27gb_candidate="not-installed-until-built-and-verified"')

$builder=Join-Path $RuntimeRoot "build-model-7.27.ps1"
Assert-Contains $builder @(
    'HF_XET_HIGH_PERFORMANCE = "1"','parallel HF/Xet parent snapshot','--no-mtp','--tensor-type-file','--dry-run',
    'tensor inventory','target_min_bytes','target_max_bytes','model-7.27.local.json','CANONICAL_FIXED',
    '125000000000L','Get-FileHash -Algorithm SHA256','llama_cpp_conversion_source.revision'
)
Assert-NotContains $builder @('Qwen3.8-27B-Uncensored-IQ2_M.gguf')

$extractor=Join-Path $RuntimeRoot "extract-quant-map.mjs"
Assert-Contains $extractor @('response.status !== 206','content-range','tensor inventory mismatch','local_inventory_checked','iq2_xxs','64 * 1024 * 1024')

$fabric=Join-Path $RuntimeRoot "execution-fabric.ps1"
Assert-Contains $fabric @('black-execution-fabric-governed-v3-7.27','decode.black-7.27-external-mtp2','canonical_status = "fixed-local-build-hash-pinned"','external_mtp_draft','decode.iq2m-fallback','vision = $false','local_parallel_slots = 1')
Assert-NotContains $fabric @('candidate_7_27gb_status')

$doctor=Join-Path $RuntimeRoot "doctor.ps1"
Assert-Contains $doctor @('BLACK CODE 7.27 GOVERNED RUNTIME DOCTOR','model-7.27.local.json','BLACK 7.27 MODEL HASH + SIZE + PARENT VERIFIED','MTP Q4_0 HASH VERIFIED','BLACK CODE DOCTOR PASS','exit 1')

$hfDownloader=Join-Path $RuntimeRoot "hf-parallel-download.ps1"
Assert-Contains $hfDownloader @('Content-Range','Start-Process','--range','chunk-{0:D2}.part','HF parallel download','Download-Sequential')
Assert-NotContains $hfDownloader @('exit 0')

$finalGate=Join-Path $RuntimeRoot "verification-gate.ps1"
Assert-Contains $finalGate @('git-diff-check','node-verify','python-pytest','cargo-test','go-test','dotnet-test','RuntimeCommand','BLACK_CODE_VERIFY=PASS','no-strong-project-or-runtime-check')
$instructions=Join-Path $RuntimeRoot "black-code-execution.md"
Assert-Contains $instructions @('WORKSPACE IS AUTHORITY','STRUCTURAL_OK','FINAL VERIFY','black-code-verify','HASH-BOUND COMPLETION','TEXT/CODE ONLY')

$temp=Join-Path ([IO.Path]::GetTempPath()) ("black-code-verify-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp|Out-Null
try {
    $telemetry=Join-Path $RuntimeRoot "opencode-telemetry.js"
    $telemetryMjs=Join-Path $temp "telemetry.mjs";Copy-Item $telemetry $telemetryMjs
    $toolLog=Join-Path $temp "tools.jsonl"
    $telemetrySmoke=Join-Path $temp "telemetry-smoke.mjs"
@'
import { pathToFileURL } from "node:url"
const [pluginPath, logPath] = process.argv.slice(2)
process.env.BLACK_CODE_TELEMETRY_PATH = logPath
const mod = await import(pathToFileURL(pluginPath).href)
const hooks = await mod.BlackCodeTelemetry()
const input = { tool:"bash", sessionID:"s", callID:"c" }
await hooks["tool.execute.before"](input,{args:{command:"pnpm test"}})
await new Promise(r=>setTimeout(r,10))
await hooks["tool.execute.after"](input,{})
'@|Set-Content -Encoding UTF8 $telemetrySmoke
    & $node $telemetrySmoke $telemetryMjs $toolLog
    if($LASTEXITCODE -ne 0 -or -not(Test-Path $toolLog)){throw "telemetry smoke failed"}
    $row=(Get-Content $toolLog|Select-Object -First 1)|ConvertFrom-Json
    if($row.kind -ne "verify" -or $row.measured -ne $true){throw "telemetry timing/classification smoke failed"}
    if($row.PSObject.Properties.Name -contains "command"){throw "telemetry persisted command content"}

    $governor=Join-Path $RuntimeRoot "opencode-governor.js"
    $governorMjs=Join-Path $temp "governor.mjs";Copy-Item $governor $governorMjs
    $govProject=Join-Path $temp "gov-project";$govState=Join-Path $temp "gov-state";New-Item -ItemType Directory -Force -Path $govProject,$govState|Out-Null
    Set-Content -Encoding UTF8 (Join-Path $govProject "state.txt") "initial"
    $govSmoke=Join-Path $temp "governor-smoke.mjs"
@'
import fs from "node:fs";import path from "node:path";import {pathToFileURL} from "node:url"
const [pluginPath,project,stateDir]=process.argv.slice(2);process.env.BLACK_CODE_PROJECT_ROOT=project;process.env.BLACK_CODE_GOVERNOR_DIR=stateDir
const mod=await import(pathToFileURL(pluginPath).href);const h=await mod.BlackCodeGovernor({directory:project,worktree:project})
const edit={tool:"write",sessionID:"s",callID:"e1"};await h["tool.execute.before"](edit,{args:{filePath:path.join(project,"state.txt")}});fs.writeFileSync(path.join(project,"state.txt"),"changed\n");await h["tool.execute.after"](edit,{metadata:{}})
const a={text:"COMPLETE"};await h["experimental.text.complete"]({sessionID:"s"},a);if(!a.text.includes("BLACK VERIFY: UNVERIFIED"))throw new Error("dirty completion allowed")
const verify={tool:"bash",sessionID:"s",callID:"v1"};await h["tool.execute.before"](verify,{args:{command:"black-code-verify"}});await h["tool.execute.after"](verify,{metadata:{exitCode:0}})
const b={text:"COMPLETE"};await h["experimental.text.complete"]({sessionID:"s"},b);if(b.text!=="COMPLETE")throw new Error("verified completion blocked")
fs.appendFileSync(path.join(project,"state.txt"),"later\n");const c={text:"COMPLETE"};await h["experimental.text.complete"]({sessionID:"s"},c);if(!c.text.includes("BLACK VERIFY: UNVERIFIED"))throw new Error("mutation did not invalidate proof")
const fail={tool:"bash",sessionID:"s",callID:"f1"};await h["tool.execute.before"](fail,{args:{command:"node -e process.exit(1)"}});await h["tool.execute.after"](fail,{metadata:{exitCode:1}});let guarded=false;try{await h["tool.execute.before"]({tool:"bash",sessionID:"s",callID:"f2"},{args:{command:"node -e process.exit(1)"}})}catch{guarded=true}if(!guarded)throw new Error("repeat guard failed")
'@|Set-Content -Encoding UTF8 $govSmoke
    & $node $govSmoke $governorMjs $govProject $govState
    if($LASTEXITCODE -ne 0){throw "governor smoke failed"}

    $ruleBridge=Join-Path $RuntimeRoot "rule-bridge.ps1";$ruleProject=Join-Path $temp "rules";New-Item -ItemType Directory -Force -Path $ruleProject|Out-Null
    Set-Content -Encoding UTF8 (Join-Path $ruleProject "CLAUDE.md") "root-rule`n@extra.md";Set-Content -Encoding UTF8 (Join-Path $ruleProject "extra.md") "imported-rule";Set-Content -Encoding UTF8 (Join-Path $ruleProject "BLACK.md") "black-rule"
    $ruleOut=Join-Path $temp "project-rules.md";& $ruleBridge -ProjectRoot $ruleProject -Destination $ruleOut|Out-Null;$ruleText=Get-Content -Raw $ruleOut
    foreach($needle in @("root-rule","imported-rule","black-rule")){if(-not $ruleText.Contains($needle)){throw "rule bridge smoke missing $needle"}}

    $gateProject=Join-Path $temp "gate";New-Item -ItemType Directory -Force -Path $gateProject|Out-Null
    '{"scripts":{"verify":"node verify.js"}}'|Set-Content -Encoding UTF8 (Join-Path $gateProject "package.json");'process.exit(0)'|Set-Content -Encoding UTF8 (Join-Path $gateProject "verify.js")
    $powershell=(Get-Command powershell.exe -ErrorAction Stop).Source;$gateOut=Join-Path $temp "gate.out";$gateErr=Join-Path $temp "gate.err"
    $p=Start-Process -FilePath $powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$finalGate,"-ProjectRoot",$gateProject) -Wait -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError $gateErr
    if($p.ExitCode -ne 0){throw "final gate smoke failed: $((Get-Content -Raw $gateErr -ErrorAction SilentlyContinue).Trim())"}
    if(-not(Get-Content -Raw $gateOut).Contains("BLACK_CODE_VERIFY=PASS")){throw "final gate PASS marker missing"}
}
finally{Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $temp}

Write-Host "BLACK Code governed 7.27 runtime verification: PASS" -ForegroundColor Green
