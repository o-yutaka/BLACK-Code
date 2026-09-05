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
    "model-7.27.lock.json","runtime.lock.json","MODEL_7_27GB.md","black-code-execution.md","analyze-bottleneck.ps1",
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

$runtimeLock=Get-Content -Raw -LiteralPath (Join-Path $RuntimeRoot "runtime.lock.json")|ConvertFrom-Json
if($runtimeLock.opencode.version -ne "1.18.28"){throw "OpenCode pin changed"}
if($runtimeLock.llama_cpp.semantic_release -ne "v0.4.0" -or $runtimeLock.llama_cpp.binary_tag -ne "b10809"){throw "llama.cpp release pin changed"}
if($runtimeLock.llama_cpp.target_commit -ne "5266f24da75dc449bd56cbed7addb9c8e4a6a73e"){throw "llama.cpp commit pin changed"}
if($runtimeLock.llama_cpp.windows_x64_main.sha256 -ne "c77bfcd9ed8d91e8721a2d6a290b907fddd4fa5412a47b21c6fa1709116b85f9"){throw "llama main asset SHA changed"}
if($runtimeLock.llama_cpp.windows_x64_cudart.sha256 -ne "8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6"){throw "llama cudart asset SHA changed"}

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
    'model-7.27.lock.json','runtime.lock.json','build-model-7.27.ps1','model-7.27.local.json','canonical-fixed',
    '[ValidateRange(1, 16)][int]$HfDownloadWorkers = 8','-HfDownloadWorkers $HfDownloadWorkers',
    'opencode-ai@','OpenCode PIN VERIFIED','llama.cpp PIN VERIFIED','Ensure-PinnedDownload','Pinned download SHA mismatch',
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf','Removed superseded model','MTP draft HASH VERIFIED',
    'hf-parallel-download.ps1','extract-quant-map.mjs','BLACK-UD-IQ2_XXS-exact-reference-map','external-draft-mtp',
    'persistent-delta-v2-untracked','workspace-runtime-bound-v3'
)
Assert-NotContains $setup @('releases?per_page=20','model_role="verified-baseline"','custom_7_27gb_candidate="not-installed-until-built-and-verified"')

$builder=Join-Path $RuntimeRoot "build-model-7.27.ps1"
Assert-Contains $builder @(
    'HF_XET_HIGH_PERFORMANCE = "1"','parallel HF/Xet parent snapshot','--no-mtp','--tensor-type-file','--dry-run',
    'tensor inventory','target_min_bytes','target_max_bytes','model-7.27.local.json','CANONICAL_FIXED',
    '125000000000L','Get-FileHash -Algorithm SHA256','llama_cpp_conversion_source.revision'
)
Assert-NotContains $builder @('Qwen3.8-27B-Uncensored-IQ2_M.gguf')

$extractor=Join-Path $RuntimeRoot "extract-quant-map.mjs"
Assert-Contains $extractor @('response.status !== 206','content-range','tensor inventory mismatch','local_inventory_checked','iq2_xxs','64 * 1024 * 1024')

$repoIndex=Join-Path $RuntimeRoot "repo-index.ps1"
Assert-Contains $repoIndex @('schema_version = "2.0"','ls-files","--others","--exclude-standard','untracked_file_count','untracked_files','New/untracked files are first-class delta','persistent')
Assert-NotContains $repoIndex @('status --porcelain=v1 -uno')

$fabric=Join-Path $RuntimeRoot "execution-fabric.ps1"
Assert-Contains $fabric @('black-execution-fabric-governed-v3-7.27','decode.black-7.27-external-mtp2','canonical_status = "fixed-local-build-hash-pinned"','external_mtp_draft','decode.iq2m-fallback','vision = $false','local_parallel_slots = 1')
Assert-NotContains $fabric @('candidate_7_27gb_status')

$governor=Join-Path $RuntimeRoot "opencode-governor.js"
Assert-Contains $governor @('runtimeFingerprint','last_runtime_hash','runtime_hash: environmentHash','governed-final-v3','workspace + runtime state','runtimeChangedSincePrior','model_manifest_hash','rules_hash','verifier_hash')

$doctor=Join-Path $RuntimeRoot "doctor.ps1"
Assert-Contains $doctor @('BLACK CODE 7.27 GOVERNED RUNTIME DOCTOR','runtime.lock.json','OpenCode PIN VERIFIED','llama.cpp PIN VERIFIED','model-7.27.local.json','BLACK 7.27 MODEL HASH + SIZE + PARENT VERIFIED','MTP Q4_0 HASH VERIFIED','persistent-delta-v2-untracked','workspace-runtime-bound-v3','BLACK CODE DOCTOR PASS','exit 1')

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

    # Repo index: untracked files must be first-class delta and affect likely-test mapping.
    $indexProject=Join-Path $temp "index-project";$indexState=Join-Path $temp "index-state";New-Item -ItemType Directory -Force -Path (Join-Path $indexProject "src"),(Join-Path $indexProject "tests"),$indexState|Out-Null
    & git -C $indexProject init -q;& git -C $indexProject config user.email "black-code-ci@example.invalid";& git -C $indexProject config user.name "BLACK Code CI"
    Set-Content -Encoding UTF8 (Join-Path $indexProject "src\base.py") "x = 1";Set-Content -Encoding UTF8 (Join-Path $indexProject "tests\test_base.py") "def test_base(): assert True"
    & git -C $indexProject add .;& git -C $indexProject commit -qm "base"
    Set-Content -Encoding UTF8 (Join-Path $indexProject "src\new.py") "y = 2";Set-Content -Encoding UTF8 (Join-Path $indexProject "tests\test_new.py") "def test_new(): assert True"
    . $repoIndex
    $idx=Get-BlackCodeRepoIndex -ProjectRoot $indexProject -IndexRoot $indexState
    if([int]$idx.index.untracked_file_count -ne 2){throw "repo index missed untracked files"}
    if(@($idx.index.changed_files) -notcontains "src/new.py"){throw "repo index omitted untracked source from delta"}
    if(@($idx.index.likely_tests) -notcontains "tests/test_new.py"){throw "repo index did not map untracked affected test"}

    $governorMjs=Join-Path $temp "governor.mjs";Copy-Item $governor $governorMjs
    $govProject=Join-Path $temp "gov-project";$govState=Join-Path $temp "governor";New-Item -ItemType Directory -Force -Path $govProject,$govState|Out-Null
    Set-Content -Encoding UTF8 (Join-Path $govProject "state.txt") "initial"
    Set-Content -Encoding UTF8 (Join-Path $temp "state.json") '{"opencode_version":"test","llama_server":"missing"}'
    Set-Content -Encoding UTF8 (Join-Path $temp "project-rules.md") "rule-v1"
    Set-Content -Encoding UTF8 (Join-Path $temp "black-code-execution.md") "instruction-v1"
    $govSmoke=Join-Path $temp "governor-smoke.mjs"
@'
import fs from "node:fs";import path from "node:path";import {pathToFileURL} from "node:url"
const [pluginPath,project,stateDir,runtimeState]=process.argv.slice(2);process.env.BLACK_CODE_PROJECT_ROOT=project;process.env.BLACK_CODE_GOVERNOR_DIR=stateDir
const mod=await import(pathToFileURL(pluginPath).href);const h=await mod.BlackCodeGovernor({directory:project,worktree:project})
const edit={tool:"write",sessionID:"s",callID:"e1"};await h["tool.execute.before"](edit,{args:{filePath:path.join(project,"state.txt")}});fs.writeFileSync(path.join(project,"state.txt"),"changed\n");await h["tool.execute.after"](edit,{metadata:{}})
const a={text:"COMPLETE"};await h["experimental.text.complete"]({sessionID:"s"},a);if(!a.text.includes("BLACK VERIFY: UNVERIFIED"))throw new Error("dirty completion allowed")
const verify={tool:"bash",sessionID:"s",callID:"v1"};await h["tool.execute.before"](verify,{args:{command:"black-code-verify"}});await h["tool.execute.after"](verify,{metadata:{exitCode:0}})
const b={text:"COMPLETE"};await h["experimental.text.complete"]({sessionID:"s"},b);if(b.text!=="COMPLETE")throw new Error("verified completion blocked")
fs.writeFileSync(runtimeState,'{"opencode_version":"changed","llama_server":"missing"}\n')
const runtimeChanged={text:"COMPLETE"};await h["experimental.text.complete"]({sessionID:"s"},runtimeChanged);if(!runtimeChanged.text.includes("BLACK VERIFY: UNVERIFIED"))throw new Error("runtime mutation did not invalidate proof")
const newSession={text:"COMPLETE"};await h["experimental.text.complete"]({sessionID:"s2"},newSession);if(!newSession.text.includes("BLACK VERIFY: UNVERIFIED"))throw new Error("runtime mutation did not carry unverified state across sessions")
const fail={tool:"bash",sessionID:"s2",callID:"f1"};await h["tool.execute.before"](fail,{args:{command:"node -e process.exit(1)"}});await h["tool.execute.after"](fail,{metadata:{exitCode:1}});let guarded=false;try{await h["tool.execute.before"]({tool:"bash",sessionID:"s2",callID:"f2"},{args:{command:"node -e process.exit(1)"}})}catch{guarded=true}if(!guarded)throw new Error("repeat guard failed")
'@|Set-Content -Encoding UTF8 $govSmoke
    & $node $govSmoke $governorMjs $govProject $govState (Join-Path $temp "state.json")
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

Write-Host "BLACK Code governed 7.27 hardening verification: PASS" -ForegroundColor Green
