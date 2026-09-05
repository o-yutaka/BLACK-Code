Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallBase = Join-Path $env:LOCALAPPDATA "BLACK-Code"
$RuntimeDir = Join-Path $InstallBase "runtime"
$LauncherDir = Join-Path $InstallBase "launcher"
$Server = Join-Path $RuntimeDir "llama\llama-server.exe"
$LockPath = Join-Path $LauncherDir "model-7.27.lock.json"
$RuntimeLockPath = Join-Path $LauncherDir "runtime.lock.json"
if (-not (Test-Path -LiteralPath $LockPath)) { Write-Host "FAIL: model-7.27.lock.json missing" -ForegroundColor Red; exit 2 }
if (-not (Test-Path -LiteralPath $RuntimeLockPath)) { Write-Host "FAIL: runtime.lock.json missing" -ForegroundColor Red; exit 2 }
$Lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$RuntimeLock = Get-Content -Raw -LiteralPath $RuntimeLockPath | ConvertFrom-Json
$Model = Join-Path $RuntimeDir ("models\" + [string]$Lock.canonical_model.file)
$ManifestPath = Join-Path $RuntimeDir "models\model-7.27.local.json"
$Draft = Join-Path $RuntimeDir ("models\" + [string]$Lock.mtp_draft.file)
$Failed = $false
$manifest = $null

function Fail([string]$Message) { $script:Failed = $true; Write-Host "FAIL: $Message" -ForegroundColor Red }
function Test-Gguf([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $stream=[IO.File]::OpenRead($Path)
    try { $bytes=New-Object byte[] 4; return $stream.Read($bytes,0,4)-eq 4 -and [Text.Encoding]::ASCII.GetString($bytes)-eq "GGUF" }
    finally { $stream.Dispose() }
}

Write-Host "=== BLACK CODE 7.27 GOVERNED RUNTIME DOCTOR ===" -ForegroundColor Cyan

Write-Host "`n[NVIDIA]"
if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) { & nvidia-smi.exe --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader }
else { Fail "nvidia-smi.exe not found" }

Write-Host "`n[RAM]"
try { $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB; Write-Host ("{0:N1} GiB" -f $ram) }
catch { Fail "RAM query failed: $($_.Exception.Message)" }

Write-Host "`n[llama.cpp pinned runtime]"
if (Test-Path $Server) {
    $llamaText=((& $Server --version 2>&1)|Out-String).Trim();Write-Host $llamaText
    $tag=[string]$RuntimeLock.llama_cpp.binary_tag;$prefix=([string]$RuntimeLock.llama_cpp.target_commit).Substring(0,8)
    if($LASTEXITCODE -ne 0){Fail "llama-server.exe failed to run"}
    elseif(($llamaText -notmatch [regex]::Escape($tag) -and $llamaText -notmatch '(?i)build\s+10809') -or $llamaText -notmatch [regex]::Escape($prefix)){Fail "llama.cpp is not the pinned $tag / $prefix runtime"}
    else{Write-Host "llama.cpp PIN VERIFIED: $tag" -ForegroundColor Green}
} else { Fail "llama-server.exe missing" }

Write-Host "`n[Canonical BLACK 7.27 model]"
if (-not (Test-Gguf $Model)) { Fail "canonical GGUF missing or invalid: $Model" }
elseif (-not (Test-Path -LiteralPath $ManifestPath)) { Fail "model-7.27.local.json missing" }
else {
    try {
        $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
        $bytes = (Get-Item -LiteralPath $Model).Length
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Model).Hash.ToLowerInvariant()
        Write-Host ("{0:N4} GB decimal / {1:N2} GiB" -f ($bytes/1e9),($bytes/1GB))
        Write-Host "SHA256: $hash"
        if ($bytes -lt [int64]$Lock.canonical_model.target_min_bytes -or $bytes -gt [int64]$Lock.canonical_model.target_max_bytes) { Fail "model is outside 7.20..7.35 GB canonical byte window" }
        elseif ($manifest.schema_version -ne "1.1") { Fail "manifest schema version mismatch" }
        elseif ($manifest.status -ne "CANONICAL_FIXED") { Fail "manifest status is not CANONICAL_FIXED" }
        elseif ($manifest.model_file -ne $Lock.canonical_model.file) { Fail "manifest model filename mismatch" }
        elseif ([int64]$manifest.model_bytes -ne $bytes) { Fail "manifest model byte count mismatch" }
        elseif (([string]$manifest.model_sha256).ToLowerInvariant() -ne $hash) { Fail "model SHA does not match local pinned manifest" }
        elseif ($manifest.no_mtp -ne $true -or $manifest.vision -ne $false) { Fail "manifest model capability fields mismatch" }
        elseif ($manifest.parent_repo -ne $Lock.uncensored_parent.repo) { Fail "uncensored parent repo mismatch" }
        elseif ($manifest.parent_revision -ne $Lock.uncensored_parent.revision) { Fail "uncensored parent revision mismatch" }
        elseif ($manifest.parent_snapshot_verified_complete -ne $true) { Fail "parent snapshot completeness is not verified" }
        elseif ($manifest.quant_map_reference_repo -ne $Lock.quant_map_reference.repo -or $manifest.quant_map_reference_revision -ne $Lock.quant_map_reference.revision) { Fail "quant map reference identity mismatch" }
        elseif (([string]$manifest.quant_map_reference_expected_full_sha256).ToLowerInvariant() -ne ([string]$Lock.quant_map_reference.sha256).ToLowerInvariant()) { Fail "quant map expected full SHA mismatch" }
        elseif ($manifest.quant_map_reference_full_sha256_measured -ne $false -or $manifest.quant_map_reference_full_downloaded -ne $false) { Fail "quant map reference must remain truthfully Range-only" }
        elseif (@($manifest.quant_map_reference_range_evidence).Count -lt 1) { Fail "quant map Range evidence is empty" }
        elseif (([string]$manifest.imatrix_sha256).ToLowerInvariant() -ne ([string]$Lock.imatrix.sha256).ToLowerInvariant()) { Fail "imatrix SHA mismatch" }
        elseif ([int64]$manifest.tensor_map_entries -lt 100 -or ([string]$manifest.tensor_map_sha256) -notmatch '^[0-9a-f]{64}$') { Fail "tensor map evidence is invalid" }
        elseif (([string]$manifest.reference_tensor_inventory_sha256) -notmatch '^[0-9a-f]{64}$') { Fail "reference tensor inventory hash is invalid" }
        elseif ([int64]$manifest.local_f16_bytes -le 0 -or ([string]$manifest.local_f16_sha256) -notmatch '^[0-9a-f]{64}$' -or $manifest.local_f16_provenance_verified -ne $true) { Fail "local F16 provenance is invalid" }
        elseif ([int64]$manifest.local_f16_tensor_count -ne [int64]$manifest.tensor_map_entries -or ([string]$manifest.local_f16_tensor_inventory_sha256) -notmatch '^[0-9a-f]{64}$' -or $manifest.local_f16_tensor_inventory_sha256 -ne $manifest.reference_tensor_inventory_sha256 -or $manifest.local_f16_names_match_reference -ne $true) { Fail "local/reference tensor inventory evidence mismatch" }
        elseif ($manifest.llama_conversion_revision -ne $Lock.llama_cpp_conversion_source.revision) { Fail "llama conversion revision mismatch" }
        elseif ($manifest.quantization -ne "BLACK-UD-IQ2_XXS exact-reference-tensor-map") { Fail "quantization policy mismatch" }
        else {
            $rangeInvalid=$false
            foreach($range in @($manifest.quant_map_reference_range_evidence)){
                if([int64]$range.received_bytes -le 0 -or [int64]$range.remote_total_bytes -le [int64]$range.received_bytes -or ([string]$range.sha256) -notmatch '^[0-9a-f]{64}$' -or ([string]$range.content_range) -notmatch '^bytes 0-[0-9]+/[0-9]+$'){$rangeInvalid=$true;Fail "quant map Range evidence entry is invalid"}
            }
            if(-not $rangeInvalid){Write-Host "BLACK 7.27 MODEL HASH + RANGE + TENSOR PROVENANCE VERIFIED" -ForegroundColor Green}
        }
    } catch { Fail "canonical model verification error: $($_.Exception.Message)" }
}

Write-Host "`n[Uncensored MTP draft]"
if (-not (Test-Gguf $Draft)) { Fail "MTP draft missing or invalid" }
else {
    $draftHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Draft).Hash.ToLowerInvariant()
    Write-Host "SHA256: $draftHash"
    if ($draftHash -eq ([string]$Lock.mtp_draft.sha256).ToLowerInvariant()) { Write-Host "MTP Q4_0 HASH VERIFIED" -ForegroundColor Green }
    else { Fail "MTP draft hash mismatch" }
}

Write-Host "`n[OpenCode pinned runtime]"
$oc = Get-Command opencode -ErrorAction SilentlyContinue
if ($oc) {
    $version=((& $oc.Source --version 2>$null)|Select-Object -First 1).ToString().Trim();Write-Host $version
    if($LASTEXITCODE -ne 0){Fail "opencode failed to run"}
    elseif($version -ne [string]$RuntimeLock.opencode.version){Fail "OpenCode version mismatch: expected $($RuntimeLock.opencode.version), got $version"}
    else {
        try {
            $npmRoot=((& npm.cmd root -g 2>$null)|Select-Object -First 1).ToString().Trim()
            $packagePath=Join-Path $npmRoot (([string]$RuntimeLock.opencode.npm_package)+"\package.json")
            $package=Get-Content -Raw -LiteralPath $packagePath|ConvertFrom-Json
            if($LASTEXITCODE -ne 0 -or $package.name -ne [string]$RuntimeLock.opencode.npm_package -or $package.version -ne [string]$RuntimeLock.opencode.version){Fail "OpenCode global package metadata does not match runtime.lock.json"}
            else{Write-Host "OpenCode PACKAGE + VERSION VERIFIED: $($package.name)@$version" -ForegroundColor Green}
        } catch { Fail "OpenCode package verification error: $($_.Exception.Message)" }
    }
} else { Fail "opencode missing" }

Write-Host "`n[Governed runtime]"
$required = @("opencode-governor.js","opencode-telemetry.js","verification-gate.ps1","rule-bridge.ps1","repo-index.ps1","hf-parallel-download.ps1","build-model-7.27.ps1","extract-quant-map.mjs","model-7.27.lock.json","runtime.lock.json")
foreach ($name in $required) {
    $path = Join-Path $LauncherDir $name
    if (Test-Path $path) { Write-Host "OK: $name" -ForegroundColor Green }
    else { Fail "$name missing" }
}
$verifyShim = Get-Command black-code-verify -ErrorAction SilentlyContinue
if ($verifyShim) { Write-Host "OK: black-code-verify shim" -ForegroundColor Green }
else { Fail "black-code-verify shim missing from PATH" }

Write-Host "`n[Canonical state]"
$statePath = Join-Path $RuntimeDir "state.json"
if (Test-Path $statePath) {
    $state=Get-Content -Raw -LiteralPath $statePath|ConvertFrom-Json
    $state|ConvertTo-Json -Depth 8
    if($state.opencode_version -ne [string]$RuntimeLock.opencode.version){Fail "state OpenCode pin mismatch"}
    if($state.llama_binary_tag -ne [string]$RuntimeLock.llama_cpp.binary_tag){Fail "state llama.cpp pin mismatch"}
    if($state.llama_commit -ne [string]$RuntimeLock.llama_cpp.target_commit){Fail "state llama.cpp commit mismatch"}
    if($state.model -ne [string]$Lock.canonical_model.file){Fail "state model filename mismatch"}
    if($null -eq $manifest){Fail "state cannot be bound to an invalid model manifest"}
    else {
        if(([string]$state.model_sha256).ToLowerInvariant() -ne ([string]$manifest.model_sha256).ToLowerInvariant()){Fail "state model SHA mismatch"}
        if([int64]$state.model_size_bytes -ne [int64]$manifest.model_bytes){Fail "state model size mismatch"}
    }
    if($state.model_parent_revision -ne [string]$Lock.uncensored_parent.revision){Fail "state model parent mismatch"}
    if($state.mtp_draft -ne [string]$Lock.mtp_draft.file){Fail "state MTP filename mismatch"}
    if(([string]$state.mtp_draft_sha256).ToLowerInvariant() -ne ([string]$Lock.mtp_draft.sha256).ToLowerInvariant()){Fail "state MTP SHA mismatch"}
    if($state.repo_index -ne "persistent-delta-v2-untracked"){Fail "state repo index version mismatch"}
    if($state.completion_governor -ne "workspace-runtime-bound-v3"){Fail "state governor version mismatch"}
} else { Fail "state.json missing; run setup.ps1" }

if ($Failed) { exit 1 }
Write-Host "`nBLACK CODE DOCTOR PASS" -ForegroundColor Green
exit 0
