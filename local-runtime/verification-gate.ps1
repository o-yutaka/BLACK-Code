param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$RuntimeCommand = "",
    [string]$RuntimeRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0

$Root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$Checks = New-Object System.Collections.Generic.List[string]
$Strength = 0

function Resolve-CommandPath([string[]]$Names) {
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    return $null
}

function Test-InGitWorkTree([string]$Path) {
    $cursor = [IO.DirectoryInfo](Resolve-Path -LiteralPath $Path).Path
    while ($cursor) {
        if (Test-Path -LiteralPath (Join-Path $cursor.FullName ".git")) { return $true }
        $cursor = $cursor.Parent
    }
    return $false
}

function Invoke-Check([string]$Name, [string]$File, [string[]]$Arguments) {
    Write-Host "[BLACK VERIFY] $Name" -ForegroundColor Cyan
    $stdout = [IO.Path]::GetTempFileName()
    $stderr = [IO.Path]::GetTempFileName()
    Push-Location $Root
    try {
        $process = Start-Process -FilePath $File -ArgumentList $Arguments -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $outText = Get-Content -Raw -LiteralPath $stdout -ErrorAction SilentlyContinue
        $errText = Get-Content -Raw -LiteralPath $stderr -ErrorAction SilentlyContinue
        if ($outText) { Write-Host $outText.TrimEnd() }
        if ($errText) { Write-Host $errText.TrimEnd() -ForegroundColor DarkYellow }
        $code = $process.ExitCode
        if ($code -ne 0) { throw "$Name failed with exit code $code" }
        [void]$Checks.Add($Name)
    }
    finally {
        Pop-Location
        Remove-Item -Force -ErrorAction SilentlyContinue $stdout, $stderr
    }
}

function Get-GitStateDigest([string]$Repository) {
    $rows = @(& $git -C $Repository status --porcelain=v1 --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Unable to read git state for $Repository" }
    $evidence = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rows) {
        if (-not $row) { continue }
        $path = ([string]$row).Substring(3)
        if ($path -match ' -> ') { $path = ($path -split ' -> ', 2)[1] }
        $path = $path.Trim('"')
        $full = Join-Path $Repository $path
        $digest = if (Test-Path -LiteralPath $full -PathType Leaf) {
            (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLowerInvariant()
        } else { "missing" }
        [void]$evidence.Add("$row`t$digest")
    }
    $text = (@($evidence) -join "`n")
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-RuntimeIntegrity([string]$Path) {
    $runtime = (Resolve-Path -LiteralPath $Path).Path
    $launcher = $PSScriptRoot
    $runtimeLockPath = Join-Path $launcher "runtime.lock.json"
    $modelLockPath = Join-Path $launcher "model-7.27.lock.json"
    $statePath = Join-Path $runtime "state.json"
    $manifestPath = Join-Path $runtime "models\model-7.27.local.json"
    foreach ($required in @($runtimeLockPath, $modelLockPath, $statePath, $manifestPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Runtime integrity input missing: $required" }
    }
    $runtimeLock = Get-Content -Raw -LiteralPath $runtimeLockPath | ConvertFrom-Json
    $modelLock = Get-Content -Raw -LiteralPath $modelLockPath | ConvertFrom-Json
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($state.canonical_runtime -ne "opencode-llama-governed-v5-black-7.27") { throw "Runtime state identity mismatch" }
    if ($state.opencode_version -ne $runtimeLock.opencode.version) { throw "Runtime state OpenCode version mismatch" }
    if ($state.llama_binary_tag -ne $runtimeLock.llama_cpp.binary_tag -or $state.llama_commit -ne $runtimeLock.llama_cpp.target_commit) { throw "Runtime state llama.cpp version mismatch" }
    if ($manifest.status -ne "CANONICAL_FIXED" -or $manifest.model_file -ne $modelLock.canonical_model.file) { throw "Canonical model manifest identity mismatch" }
    if ($manifest.parent_revision -ne $modelLock.uncensored_parent.revision) { throw "Canonical model manifest parent mismatch" }
    if ($state.model -ne $manifest.model_file -or $state.model_sha256 -ne $manifest.model_sha256 -or [int64]$state.model_size_bytes -ne [int64]$manifest.model_bytes) { throw "Runtime state/model manifest mismatch" }
    $opencode = Resolve-CommandPath @("opencode.cmd", "opencode.exe", "opencode")
    if (-not $opencode) { throw "Pinned OpenCode runtime was not found" }
    $global:LASTEXITCODE = 0
    $actualOpenCode = ((& $opencode --version 2>$null | Select-Object -First 1) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualOpenCode -ne [string]$runtimeLock.opencode.version) { throw "OpenCode runtime version mismatch: expected $($runtimeLock.opencode.version), got $actualOpenCode" }
    $server = [string]$state.llama_server
    if (-not (Test-Path -LiteralPath $server -PathType Leaf)) { throw "Pinned llama-server runtime was not found: $server" }
    $global:LASTEXITCODE = 0
    $llamaVersion = ((& $server --version 2>&1) | Out-String).Trim()
    $commitPrefix = ([string]$runtimeLock.llama_cpp.target_commit).Substring(0, 8)
    if ($LASTEXITCODE -ne 0 -or ($llamaVersion -notmatch [regex]::Escape([string]$runtimeLock.llama_cpp.binary_tag) -and $llamaVersion -notmatch [regex]::Escape($commitPrefix) -and $llamaVersion -notmatch '(?i)build\s+10809')) { throw "llama.cpp runtime version mismatch" }
    [void]$Checks.Add("runtime-integrity")
}

function Invoke-RuntimeCheck([string]$Command) {
    $normalized = ($Command.Trim() -replace '\s+', ' ')
    if (-not $normalized) { return }
    if ($normalized -match '(?i)^(echo\b|true\b|exit\s+0\b|pwd\b|cd\b|git\s+(status|diff)\b)') {
        throw "RuntimeCommand is a no-op and cannot satisfy final verification: $normalized"
    }
    $cmd = Resolve-CommandPath @("cmd.exe", "cmd")
    if (-not $cmd) { throw "cmd.exe was not found for RuntimeCommand verification." }
    Invoke-Check "runtime-entrypoint" $cmd @("/d", "/s", "/c", $Command)
}

$git = Resolve-CommandPath @("git.exe", "git")
if (-not $git) {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe")
    )) { if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { $git = $candidate; break } }
}
$projectHasGitMetadata = Test-InGitWorkTree $Root
if ($projectHasGitMetadata -and -not $git) { throw "Git worktree detected but git is unavailable; final verification cannot prove workspace stability." }
$gitRepo = $false
if ($git) {
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $inside = & $git -C $Root rev-parse --is-inside-work-tree 2>$null
        $gitRepo = ($LASTEXITCODE -eq 0) -and ([Convert]::ToString($inside).Trim() -eq "true")
    }
    finally { $ErrorActionPreference = $previousErrorAction }
}
if ($projectHasGitMetadata -and -not $gitRepo) { throw "Git worktree could not be inspected; final verification cannot prove tracked or untracked workspace stability." }
if ($gitRepo) {
    Invoke-Check "git-diff-check" $git @("-C", $Root, "diff", "--check")
}

$sourceRepo = $false
if ($git) {
    $sourceInside = & $git -C $PSScriptRoot rev-parse --is-inside-work-tree 2>$null
    $sourceRepo = ($LASTEXITCODE -eq 0) -and ([Convert]::ToString($sourceInside).Trim() -eq "true")
}
$sourceHasGitMetadata = Test-InGitWorkTree $PSScriptRoot
if ($sourceHasGitMetadata -and -not $sourceRepo) { throw "BLACK Code runtime source worktree could not be inspected; VERIFIED is forbidden." }
if ($sourceRepo) {
    $sourceStatus = @(& $git -C $PSScriptRoot status --porcelain=v1 --untracked-files=all -- . 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect BLACK Code runtime source" }
    if ($sourceStatus.Count -gt 0) { throw "BLACK Code runtime source is dirty (tracked or untracked); VERIFIED is forbidden.`n$($sourceStatus -join "`n")" }
    [void]$Checks.Add("runtime-source-clean")
}

if (-not $RuntimeRoot -and $env:LOCALAPPDATA) {
    $candidate = Join-Path $env:LOCALAPPDATA "BLACK-Code\runtime"
    $hasLauncherLocks = (Test-Path -LiteralPath (Join-Path $PSScriptRoot "runtime.lock.json")) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot "model-7.27.lock.json"))
    if ($hasLauncherLocks -and ((Test-Path -LiteralPath (Join-Path $candidate "state.json")) -or (Test-Path -LiteralPath (Join-Path $candidate "models\model-7.27.local.json")))) { $RuntimeRoot = $candidate }
}
if ($RuntimeRoot) { Assert-RuntimeIntegrity $RuntimeRoot }

$projectStateBefore = if ($gitRepo) { Get-GitStateDigest $Root } else { $null }

$packageJson = Join-Path $Root "package.json"
$pyproject = Join-Path $Root "pyproject.toml"
$requirements = Join-Path $Root "requirements.txt"
$cargoToml = Join-Path $Root "Cargo.toml"
$goMod = Join-Path $Root "go.mod"
$dotnetProject = Get-ChildItem -LiteralPath $Root -Filter "*.sln" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $dotnetProject) { $dotnetProject = Get-ChildItem -LiteralPath $Root -Filter "*.csproj" -File -ErrorAction SilentlyContinue | Select-Object -First 1 }

if (Test-Path -LiteralPath $packageJson) {
    $package = Get-Content -Raw -LiteralPath $packageJson | ConvertFrom-Json
    $scripts = $package.scripts
    $runner = $null
    $prefix = @()
    if (Test-Path (Join-Path $Root "pnpm-lock.yaml")) { $runner = Resolve-CommandPath @("pnpm.cmd", "pnpm"); $prefix = @("run") }
    elseif (Test-Path (Join-Path $Root "yarn.lock")) { $runner = Resolve-CommandPath @("yarn.cmd", "yarn"); $prefix = @() }
    elseif ((Test-Path (Join-Path $Root "bun.lockb")) -or (Test-Path (Join-Path $Root "bun.lock"))) { $runner = Resolve-CommandPath @("bun.exe", "bun"); $prefix = @("run") }
    else { $runner = Resolve-CommandPath @("npm.cmd", "npm"); $prefix = @("run") }
    if (-not $runner) { throw "Node package detected but no package manager command is available." }

    $available = @()
    if ($scripts) { $available = @($scripts.PSObject.Properties.Name) }
    if ($available -contains "verify") {
        Invoke-Check "node-verify" $runner ($prefix + @("verify"))
        $Strength = [Math]::Max($Strength, 3)
    }
    else {
        foreach ($name in @("typecheck", "lint", "test", "build")) {
            if ($available -contains $name) {
                Invoke-Check "node-$name" $runner ($prefix + @($name))
                if ($name -in @("test", "build")) { $Strength = [Math]::Max($Strength, 3) }
                else { $Strength = [Math]::Max($Strength, 2) }
            }
        }
    }
}
elseif ((Test-Path -LiteralPath $pyproject) -or (Test-Path -LiteralPath $requirements)) {
    $python = Resolve-CommandPath @("python.exe", "python", "py.exe", "py")
    if (-not $python) { throw "Python project detected but Python was not found." }
    $changedPython = @()
    if ($gitRepo) {
        $changedPython = @(& $git -C $Root diff --name-only HEAD -- "*.py" 2>$null)
        $changedPython += @(& $git -C $Root ls-files --others --exclude-standard -- "*.py" 2>$null)
    }
    $changedPython = @($changedPython | Where-Object { $_ } | Sort-Object -Unique | Select-Object -First 200)
    if ($changedPython.Count -eq 0) {
        $changedPython = @(Get-ChildItem -LiteralPath $Root -Filter "*.py" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/](\.venv|venv|node_modules|__pycache__|build|dist)[\\/]' } |
            Select-Object -First 200 |
            ForEach-Object { $_.FullName })
    }
    foreach ($file in $changedPython) {
        $target = if ([IO.Path]::IsPathRooted([string]$file)) { [string]$file } else { Join-Path $Root ([string]$file) }
        if (Test-Path -LiteralPath $target) { Invoke-Check "python-compile:$([IO.Path]::GetFileName($target))" $python @("-m", "py_compile", $target) }
    }
    $pytest = $false
    Push-Location $Root
    try {
        & $python -m pytest --version *> $null
        $pytest = $LASTEXITCODE -eq 0
    }
    finally { Pop-Location }
    $hasTests = (Test-Path (Join-Path $Root "tests")) -or (Test-Path (Join-Path $Root "test"))
    if ($pytest -and $hasTests) {
        Invoke-Check "python-pytest" $python @("-m", "pytest", "-q")
        $Strength = [Math]::Max($Strength, 3)
    }
    elseif ($changedPython.Count -gt 0) {
        $Strength = [Math]::Max($Strength, 1)
    }
}
elseif (Test-Path -LiteralPath $cargoToml) {
    $cargo = Resolve-CommandPath @("cargo.exe", "cargo")
    if (-not $cargo) { throw "Cargo.toml detected but cargo was not found." }
    Invoke-Check "cargo-check" $cargo @("check")
    Invoke-Check "cargo-test" $cargo @("test")
    $Strength = 3
}
elseif (Test-Path -LiteralPath $goMod) {
    $go = Resolve-CommandPath @("go.exe", "go")
    if (-not $go) { throw "go.mod detected but go was not found." }
    Invoke-Check "go-test" $go @("test", "./...")
    $Strength = 3
}
elseif ($dotnetProject) {
    $dotnet = Resolve-CommandPath @("dotnet.exe", "dotnet")
    if (-not $dotnet) { throw ".NET project detected but dotnet was not found." }
    Invoke-Check "dotnet-test" $dotnet @("test")
    $Strength = 3
}

if ($RuntimeCommand.Trim()) {
    Invoke-RuntimeCheck $RuntimeCommand
    $Strength = [Math]::Max($Strength, 3)
}

if ($gitRepo) {
    $projectStateAfter = Get-GitStateDigest $Root
    if ($projectStateAfter -ne $projectStateBefore) { throw "Project files changed during final verification; rerun verification against the final state." }
}

if ($Strength -lt 3) {
    Write-Host "BLACK_CODE_VERIFY=BLOCKED reason=no-strong-project-or-runtime-check" -ForegroundColor Yellow
    Write-Host 'Provide a task-relevant runtime check with: black-code-verify -RuntimeCommand "<real entrypoint/smoke command>"' -ForegroundColor Yellow
    exit 3
}

$result = [ordered]@{
    schema_version = "2.0"
    status = "PASS"
    profile = "governed-final-v2"
    project_root = $Root
    checks = @($Checks)
    strength = $Strength
}
Write-Host ("BLACK_CODE_VERIFY=PASS " + ($result | ConvertTo-Json -Compress)) -ForegroundColor Green
exit 0
