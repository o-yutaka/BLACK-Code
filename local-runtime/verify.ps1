Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RuntimeRoot = $PSScriptRoot

function Assert-Contains([string]$Path, [string[]]$Needles) {
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($needle in $Needles) {
        if (-not $content.Contains($needle)) { throw "Missing contract '$needle' in $Path" }
    }
}

function Assert-NotContains([string]$Path, [string[]]$Needles) {
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($needle in $Needles) {
        if ($content.Contains($needle)) { throw "Rejected runtime contract '$needle' is present in $Path" }
    }
}

$files = @(
    (Join-Path $RuntimeRoot "black-code.ps1"),
    (Join-Path $RuntimeRoot "setup.ps1"),
    (Join-Path $RuntimeRoot "doctor.ps1"),
    (Join-Path $RuntimeRoot "execution-fabric.ps1"),
    (Join-Path $RuntimeRoot "repo-index.ps1"),
    (Join-Path $RuntimeRoot "verify.ps1")
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Required runtime file is missing: $file" }
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
    $errorList = @($parseErrors)
    if ($errorList.Count -gt 0) {
        foreach ($parseError in $errorList) {
            Write-Host ("{0}:{1}:{2}: {3} :: {4}" -f $file, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message, $parseError.Extent.Text)
        }
        throw "PowerShell parse failed: $file"
    }
}

$launcher = Join-Path $RuntimeRoot "black-code.ps1"
Assert-Contains $launcher @(
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf',
    '. (Resolve-RuntimeFile "repo-index.ps1")',
    'Get-BlackCodeRepoIndex',
    'instructions = @("black-code-execution.md", "repo-context.md")',
    '$trackedFileCount -le 150',
    '$Context = 8192',
    '$trackedFileCount -le 800',
    '$Context = 12288',
    '$Context = 16384',
    '"--spec-type", "draft-mtp"',
    '"--spec-draft-n-max", "2"',
    '"--fit-ctx", "$Context"',
    'explicit split OFF',
    'Write-BlackCodeSessionEvidence'
)
Assert-NotContains $launcher @(
    '$ModelFile = "Qwen3.8-27B-Uncensored-IQ4_XS.gguf"',
    '"--spec-type", "draft-mtp,ngram-mod"',
    '"--cache-reuse"',
    '"--tensor-split"',
    '"-ts"'
)

$index = Join-Path $RuntimeRoot "repo-index.ps1"
Assert-Contains $index @(
    'cache_status = "HIT"',
    '"DELTA_REFRESH"',
    '"MISS_BUILD"',
    'diff --name-only',
    'package_roots',
    'likely_tests',
    'repo-context.md'
)

$instructions = Join-Path $RuntimeRoot "black-code-execution.md"
Assert-Contains $instructions @(
    'INDEX FIRST',
    'repo-context.md',
    'DELTA CONTEXT',
    'AFFECTED VERIFY',
    'MINIMIZE MODEL CALLS'
)

$setup = Join-Path $RuntimeRoot "setup.ps1"
Assert-Contains $setup @(
    '$ModelFile = "Qwen3.8-27B-Uncensored-IQ2_M.gguf"',
    '28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187',
    '"repo-index.ps1"',
    'repo_index = "persistent-delta-v1"',
    'default_context = "auto-8192-12288-16384"',
    'mtp_draft_max = 2'
)

$doctor = Join-Path $RuntimeRoot "doctor.ps1"
Assert-Contains $doctor @(
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf',
    '28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187',
    'IQ2_M HASH VERIFIED'
)

Write-Host "BLACK CODE PERSISTENT DELTA INDEX STATIC VERIFY: PASS" -ForegroundColor Green
