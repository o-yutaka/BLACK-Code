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
function Invoke-Native([string]$File,[string[]]$Arguments,[string]$Label) {
    $quoted=@($Arguments|ForEach-Object{'"'+([string]$_).Replace('"','\"')+'"'}) -join ' '
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$File;$info.Arguments=$quoted;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$info
    if(-not $process.Start()){throw "$Label failed to start"}
    $stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
    $process.WaitForExit();$captured=$stdoutTask.Result;$errorText=$stderrTask.Result
    if($process.ExitCode -ne 0){throw "$Label failed with exit code $($process.ExitCode): $(($errorText+$captured).Trim())"}
    if($captured){Write-Output $captured}
}

$requiredFiles=@(
    "black-code.ps1","setup.ps1","doctor.ps1","execution-fabric.ps1","repo-index.ps1","rule-bridge.ps1",
    "verification-gate.ps1","hf-parallel-download.ps1","build-model-7.27.ps1","extract-quant-map.mjs",
    "model-7.27.lock.json","runtime.lock.json","MODEL_7_27GB.md","black-code-execution.md","black-code-rules.md","analyze-bottleneck.ps1",
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
    $syntaxTarget=Join-Path $RuntimeRoot $jsName;$syntaxCopy=$null
    if([IO.Path]::GetExtension($syntaxTarget) -eq ".js"){$syntaxCopy=Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName()+".mjs");Copy-Item $syntaxTarget $syntaxCopy;$syntaxTarget=$syntaxCopy}
    try {Invoke-Native $node @("--check",$syntaxTarget) "Node syntax check: $jsName"}
    finally {if($syntaxCopy){Remove-Item -Force -ErrorAction SilentlyContinue $syntaxCopy}}
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
Assert-Contains $extractor @('response.status !== 206','content-range','tensor inventory mismatch','tensor_inventory_sha256','names_match_reference','fetched_ranges','full_reference_downloaded: false','full_reference_sha256_measured: false','iq2_xxs','64 * 1024 * 1024')

$repoIndex=Join-Path $RuntimeRoot "repo-index.ps1"
Assert-Contains $repoIndex @('schema_version = "2.0"','ls-files","--others","--exclude-standard','untracked_file_count','untracked_files','New/untracked files are first-class delta','persistent')
Assert-NotContains $repoIndex @('status --porcelain=v1 -uno')

$fabric=Join-Path $RuntimeRoot "execution-fabric.ps1"
Assert-Contains $fabric @('black-execution-fabric-governed-v3-7.27','decode.black-7.27-external-mtp2','canonical_status = "fixed-local-build-hash-pinned"','external_mtp_draft','decode.iq2m-fallback','vision = $false','local_parallel_slots = 1')
Assert-NotContains $fabric @('candidate_7_27gb_status')

$governor=Join-Path $RuntimeRoot "opencode-governor.js"
Assert-Contains $governor @('runtimeFingerprint','last_runtime_hash','runtime_hash: environmentHash','governed-final-v3','workspace + runtime state','runtimeChangedSincePrior','model_manifest_hash','rules_hash','verifier_hash')

$doctor=Join-Path $RuntimeRoot "doctor.ps1"
Assert-Contains $doctor @('BLACK CODE 7.27 GOVERNED RUNTIME DOCTOR','runtime.lock.json','OpenCode PACKAGE + VERSION VERIFIED','OpenCode global package metadata does not match runtime.lock.json','llama.cpp PIN VERIFIED','model-7.27.local.json','manifest schema version mismatch','parent snapshot completeness is not verified','BLACK 7.27 MODEL HASH + RANGE + TENSOR PROVENANCE VERIFIED','MTP Q4_0 HASH VERIFIED','persistent-delta-v2-untracked','workspace-runtime-bound-v3','BLACK CODE DOCTOR PASS','exit 1')

$hfDownloader=Join-Path $RuntimeRoot "hf-parallel-download.ps1"
Assert-Contains $hfDownloader @('Content-Range','Start-Process','--range','chunk-{0:D2}.part','HF parallel download','Download-Sequential')
Assert-NotContains $hfDownloader @('exit 0')

$finalGate=Join-Path $RuntimeRoot "verification-gate.ps1"
Assert-Contains $finalGate @('git-diff-check','node-verify','python-pytest','cargo-test','go-test','dotnet-test','RuntimeCommand','BLACK_CODE_VERIFY=PASS','no-strong-project-or-runtime-check','runtime-source-clean','Runtime state/model manifest mismatch','OpenCode runtime version mismatch','Project files changed during final verification')
$instructions=Join-Path $RuntimeRoot "black-code-execution.md"
Assert-Contains $instructions @('WORKSPACE IS AUTHORITY','STRUCTURAL_OK','FINAL VERIFY','black-code-verify','HASH-BOUND COMPLETION','TEXT/CODE ONLY')

$verifyTempRoot=if($env:BLACK_CODE_VERIFY_TEMP_ROOT){$env:BLACK_CODE_VERIFY_TEMP_ROOT}else{[IO.Path]::GetTempPath()}
$temp=Join-Path $verifyTempRoot ("black-code-verify-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp|Out-Null
try {
    $telemetry=Join-Path $RuntimeRoot "opencode-telemetry.js"
    $telemetryMjs=Join-Path $temp "telemetry.mjs";Copy-Item $telemetry $telemetryMjs
    $toolLog=Join-Path $temp "tools.jsonl"
    $telemetrySmoke=Join-Path $temp "telemetry-smoke.mjs"
@'
import fs from "node:fs"
import { pathToFileURL } from "node:url"
const [pluginPath, logPath] = process.argv.slice(2)
process.env.BLACK_CODE_TELEMETRY_PATH = logPath
const mod = await import(pathToFileURL(pluginPath).href)
const hooks = await mod.BlackCodeTelemetry()
const input = { tool:"bash", sessionID:"s", callID:"c" }
await hooks["tool.execute.before"](input,{args:{command:"pnpm test"}})
await new Promise(r=>setTimeout(r,10))
await hooks["tool.execute.after"](input,{})
if (!fs.existsSync(logPath)) throw new Error(`telemetry evidence missing at ${logPath}`)
process.stdout.write(fs.readFileSync(logPath, "utf8"))
'@|Set-Content -Encoding UTF8 $telemetrySmoke
    $telemetryOutput=Invoke-Native $node @($telemetrySmoke,$telemetryMjs,$toolLog) "telemetry smoke"
    $telemetryJson=($telemetryOutput|Out-String).Trim()
    $row=$telemetryJson|ConvertFrom-Json
    if(-not($row.PSObject.Properties.Name -contains "kind")){throw "telemetry smoke returned invalid evidence: $telemetryJson"}
    if($row.kind -ne "verify" -or $row.measured -ne $true){throw "telemetry timing/classification smoke failed"}
    if($row.PSObject.Properties.Name -contains "command"){throw "telemetry persisted command content"}

    # Repo index: untracked files must be first-class delta and affect likely-test mapping.
    $indexProject=Join-Path $temp "index-project";$indexState=Join-Path $temp "index-state";New-Item -ItemType Directory -Force -Path (Join-Path $indexProject "src"),(Join-Path $indexProject "tests"),$indexState|Out-Null
    $gitCommand=(Get-Command git.exe -ErrorAction SilentlyContinue).Source;if(-not $gitCommand){$gitCommand=Join-Path $env:ProgramFiles "Git\cmd\git.exe"};if(-not(Test-Path -LiteralPath $gitCommand)){throw "Git executable not found for verification smoke"}
    Invoke-Native $gitCommand @("-C",$indexProject,"init","-q") "index git init";Invoke-Native $gitCommand @("-C",$indexProject,"config","user.email","black-code-ci@example.invalid") "index git config email";Invoke-Native $gitCommand @("-C",$indexProject,"config","user.name","BLACK Code CI") "index git config name"
    Set-Content -Encoding UTF8 (Join-Path $indexProject "src\base.py") "x = 1";Set-Content -Encoding UTF8 (Join-Path $indexProject "tests\test_base.py") "def test_base(): assert True"
    Invoke-Native $gitCommand @("-C",$indexProject,"add",".") "index git add";Invoke-Native $gitCommand @("-C",$indexProject,"commit","-qm","base") "index git commit"
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
    Invoke-Native $node @($govSmoke,$governorMjs,$govProject,$govState,(Join-Path $temp "state.json")) "governor smoke"

    $ruleBridge=Join-Path $RuntimeRoot "rule-bridge.ps1";$ruleProject=Join-Path $temp "rules";New-Item -ItemType Directory -Force -Path $ruleProject|Out-Null
    Set-Content -Encoding UTF8 (Join-Path $ruleProject "CLAUDE.md") "root-rule`n@extra.md";Set-Content -Encoding UTF8 (Join-Path $ruleProject "extra.md") "imported-rule";Set-Content -Encoding UTF8 (Join-Path $ruleProject "BLACK.md") "black-rule"
    $ruleOut=Join-Path $temp "project-rules.md";& $ruleBridge -ProjectRoot $ruleProject -Destination $ruleOut|Out-Null;$ruleText=Get-Content -Raw $ruleOut
    foreach($needle in @("root-rule","imported-rule","black-rule")){if(-not $ruleText.Contains($needle)){throw "rule bridge smoke missing $needle"}}

    $gateProject=Join-Path $temp "gate";New-Item -ItemType Directory -Force -Path $gateProject|Out-Null
    Invoke-Native $gitCommand @("-C",$gateProject,"init","-q") "gate git init";Invoke-Native $gitCommand @("-C",$gateProject,"config","user.email","black-code-ci@example.invalid") "gate git config email";Invoke-Native $gitCommand @("-C",$gateProject,"config","user.name","BLACK Code CI") "gate git config name"
    '{"scripts":{"verify":"node verify.js"}}'|Set-Content -Encoding UTF8 (Join-Path $gateProject "package.json");'process.exit(0)'|Set-Content -Encoding UTF8 (Join-Path $gateProject "verify.js")
    Invoke-Native $gitCommand @("-C",$gateProject,"add",".") "gate git add";Invoke-Native $gitCommand @("-C",$gateProject,"commit","-qm","gate fixture") "gate git commit"
    $gateSource=Join-Path $temp "gate-source";New-Item -ItemType Directory -Force -Path $gateSource|Out-Null
    $gateUnderTest=Join-Path $gateSource "verification-gate.ps1";Copy-Item $finalGate $gateUnderTest
    $powershell=(Get-Command powershell.exe -ErrorAction Stop).Source;$gateOut=Join-Path $temp "gate.out";$gateErr=Join-Path $temp "gate.err"
    $p=Start-Process -FilePath $powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$gateUnderTest,"-ProjectRoot",$gateProject) -Wait -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError $gateErr
    if($p.ExitCode -ne 0){throw "final gate smoke failed: $((Get-Content -Raw $gateErr -ErrorAction SilentlyContinue).Trim())"}
    if(-not(Get-Content -Raw $gateOut).Contains("BLACK_CODE_VERIFY=PASS")){throw "final gate PASS marker missing"}

    # A nominally successful verifier that edits the tree must never yield VERIFIED.
    'require("node:fs").writeFileSync("post-verify.txt","changed");process.exit(0)'|Set-Content -Encoding UTF8 (Join-Path $gateProject "verify.js")
    Invoke-Native $gitCommand @("-C",$gateProject,"add","verify.js") "mutation git add";Invoke-Native $gitCommand @("-C",$gateProject,"commit","-qm","mutating verifier") "mutation git commit"
    $p=Start-Process -FilePath $powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$gateUnderTest,"-ProjectRoot",$gateProject) -Wait -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError $gateErr
    if($p.ExitCode -eq 0 -or (Get-Content -Raw $gateOut -ErrorAction SilentlyContinue).Contains("BLACK_CODE_VERIFY=PASS")){throw "post-verification workspace mutation incorrectly passed"}

    # A failing strong check must never emit the PASS marker.
    'process.exit(9)'|Set-Content -Encoding UTF8 (Join-Path $gateProject "verify.js")
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $gateProject "post-verify.txt")
    $p=Start-Process -FilePath $powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$gateUnderTest,"-ProjectRoot",$gateProject) -Wait -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError $gateErr
    if($p.ExitCode -eq 0 -or (Get-Content -Raw $gateOut -ErrorAction SilentlyContinue).Contains("BLACK_CODE_VERIFY=PASS")){throw "failing project verifier incorrectly passed"}

    # Runtime state and model manifest are mutually pinned; either mismatch must fail closed.
    Copy-Item (Join-Path $RuntimeRoot "runtime.lock.json") $gateSource;Copy-Item (Join-Path $RuntimeRoot "model-7.27.lock.json") $gateSource
    $fakeRuntime=Join-Path $temp "fake-runtime";New-Item -ItemType Directory -Force -Path (Join-Path $fakeRuntime "models")|Out-Null
    $runtimeLock=Get-Content -Raw (Join-Path $RuntimeRoot "runtime.lock.json")|ConvertFrom-Json;$modelLock=Get-Content -Raw (Join-Path $RuntimeRoot "model-7.27.lock.json")|ConvertFrom-Json
    $fakeState=[ordered]@{canonical_runtime="opencode-llama-governed-v5-black-7.27";opencode_version=$runtimeLock.opencode.version;llama_binary_tag=$runtimeLock.llama_cpp.binary_tag;llama_commit=$runtimeLock.llama_cpp.target_commit;model=$modelLock.canonical_model.file;model_sha256="same";model_size_bytes=1;llama_server="missing.exe"}
    $fakeManifest=[ordered]@{status="NOT_CANONICAL";model_file=$modelLock.canonical_model.file;parent_revision=$modelLock.uncensored_parent.revision;model_sha256="same";model_bytes=1}
    $fakeState|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $fakeRuntime "state.json");$fakeManifest|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $fakeRuntime "models\model-7.27.local.json")
    $plainProject=Join-Path $temp "plain-project";New-Item -ItemType Directory -Force -Path $plainProject|Out-Null;'{"scripts":{"verify":"node verify.js"}}'|Set-Content -Encoding UTF8 (Join-Path $plainProject "package.json");'process.exit(0)'|Set-Content -Encoding UTF8 (Join-Path $plainProject "verify.js")
    $p=Start-Process -FilePath $powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$gateUnderTest,"-ProjectRoot",$plainProject,"-RuntimeRoot",$fakeRuntime) -Wait -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError $gateErr
    $failureText=(Get-Content -Raw $gateErr -ErrorAction SilentlyContinue)+(Get-Content -Raw $gateOut -ErrorAction SilentlyContinue)
    if($p.ExitCode -eq 0 -or -not $failureText.Contains("Canonical model manifest identity mismatch")){throw "model manifest mismatch did not fail closed"}
    $fakeState.opencode_version="wrong-version";$fakeState|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $fakeRuntime "state.json");$fakeManifest.status="CANONICAL_FIXED";$fakeManifest|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $fakeRuntime "models\model-7.27.local.json")
    $p=Start-Process -FilePath $powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$gateUnderTest,"-ProjectRoot",$plainProject,"-RuntimeRoot",$fakeRuntime) -Wait -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError $gateErr
    $failureText=(Get-Content -Raw $gateErr -ErrorAction SilentlyContinue)+(Get-Content -Raw $gateOut -ErrorAction SilentlyContinue)
    if($p.ExitCode -eq 0 -or -not $failureText.Contains("Runtime state OpenCode version mismatch")){throw "runtime version mismatch did not fail closed"}

    # Dirty tracked or untracked BLACK runtime source must be rejected before project checks.
    $dirtySource=Join-Path $temp "dirty-runtime";New-Item -ItemType Directory -Force -Path $dirtySource|Out-Null
    Copy-Item $finalGate (Join-Path $dirtySource "verification-gate.ps1");Invoke-Native $gitCommand @("-C",$dirtySource,"init","-q") "dirty-source git init";Invoke-Native $gitCommand @("-C",$dirtySource,"config","user.email","black-code-ci@example.invalid") "dirty-source git config email";Invoke-Native $gitCommand @("-C",$dirtySource,"config","user.name","BLACK Code CI") "dirty-source git config name";Invoke-Native $gitCommand @("-C",$dirtySource,"add",".") "dirty-source git add";Invoke-Native $gitCommand @("-C",$dirtySource,"commit","-qm","clean runtime") "dirty-source git commit"
    Set-Content -Encoding UTF8 (Join-Path $dirtySource "untracked-runtime.ps1") 'Write-Host "dirty"'
    $p=Start-Process -FilePath $powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",(Join-Path $dirtySource "verification-gate.ps1"),"-ProjectRoot",$gateProject) -Wait -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError $gateErr
    if($p.ExitCode -eq 0 -or (Get-Content -Raw $gateOut -ErrorAction SilentlyContinue).Contains("BLACK_CODE_VERIFY=PASS")){throw "dirty runtime source incorrectly passed"}
}
finally{Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $temp}

Write-Host "BLACK Code governed 7.27 hardening verification: PASS" -ForegroundColor Green
