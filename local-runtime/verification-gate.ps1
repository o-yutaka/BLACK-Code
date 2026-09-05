param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$RuntimeCommand = ""
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

function Invoke-Check([string]$Name, [string]$File, [string[]]$Arguments) {
    Write-Host "[BLACK VERIFY] $Name" -ForegroundColor Cyan
    Push-Location $Root
    try {
        & $File @Arguments
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        if ($code -ne 0) { throw "$Name failed with exit code $code" }
        [void]$Checks.Add($Name)
    }
    finally { Pop-Location }
}

function Invoke-RuntimeCheck([string]$Command) {
    $normalized = ($Command.Trim() -replace '\s+', ' ')
    if (-not $normalized) { return }
    if ($normalized -match '^(?i)(echo\b|true\b|exit\s+0\b|pwd\b|cd\b|git\s+(status|diff)\b)') {
        throw "RuntimeCommand is a no-op and cannot satisfy final verification: $normalized"
    }
    $cmd = Resolve-CommandPath @("cmd.exe", "cmd")
    if (-not $cmd) { throw "cmd.exe was not found for RuntimeCommand verification." }
    Invoke-Check "runtime-entrypoint" $cmd @("/d", "/s", "/c", $Command)
}

$git = Resolve-CommandPath @("git.exe", "git")
if ($git) {
    Invoke-Check "git-diff-check" $git @("-C", $Root, "diff", "--check")
}

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
elif ((Test-Path -LiteralPath $pyproject) -or (Test-Path -LiteralPath $requirements)) {
    $python = Resolve-CommandPath @("python.exe", "python", "py.exe", "py")
    if (-not $python) { throw "Python project detected but Python was not found." }
    $changedPython = @()
    if ($git) {
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
elif (Test-Path -LiteralPath $cargoToml) {
    $cargo = Resolve-CommandPath @("cargo.exe", "cargo")
    if (-not $cargo) { throw "Cargo.toml detected but cargo was not found." }
    Invoke-Check "cargo-check" $cargo @("check")
    Invoke-Check "cargo-test" $cargo @("test")
    $Strength = 3
}
elif (Test-Path -LiteralPath $goMod) {
    $go = Resolve-CommandPath @("go.exe", "go")
    if (-not $go) { throw "go.mod detected but go was not found." }
    Invoke-Check "go-test" $go @("test", "./...")
    $Strength = 3
}
elif ($dotnetProject) {
    $dotnet = Resolve-CommandPath @("dotnet.exe", "dotnet")
    if (-not $dotnet) { throw ".NET project detected but dotnet was not found." }
    Invoke-Check "dotnet-test" $dotnet @("test")
    $Strength = 3
}

if ($RuntimeCommand.Trim()) {
    Invoke-RuntimeCheck $RuntimeCommand
    $Strength = [Math]::Max($Strength, 3)
}

if ($Strength -lt 3) {
    Write-Host "BLACK_CODE_VERIFY=BLOCKED reason=no-strong-project-or-runtime-check" -ForegroundColor Yellow
    Write-Host "Provide a task-relevant runtime check with: black-code-verify -RuntimeCommand \"<real entrypoint/smoke command>\"" -ForegroundColor Yellow
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
