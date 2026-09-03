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
    (Join-Path $RuntimeRoot "execution-fabric.ps1"),
    (Join-Path $RuntimeRoot "verify.ps1")
)

foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Required runtime file is missing: $file" }
    $tokens = $null
    $parseErrors = $null
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
    '"--spec-type", "draft-mtp"',
    '--spec-draft-n-max',
    'MTP max 2',
    'black-code-execution.md',
    'New-BlackCodeExecutionProfile',
    'Write-BlackCodeSessionEvidence'
)
Assert-NotContains $launcher @(
    'Qwen3.8-27B-Uncensored-IQ4_XS.gguf',
    '"--spec-type", "draft-mtp,ngram-mod"',
    '"--spec-ngram-mod-n-match"',
    '"--cache-reuse"'
)

$fabric = Join-Path $RuntimeRoot "execution-fabric.ps1"
Assert-Contains $fabric @(
    'black-execution-fabric-iq2m-fast-v1',
    'decode.mtp2',
    'task.atomize',
    'work.dedupe-overlap',
    'context.reuse-session',
    'tool.prefetch-batch',
    'verify.targeted-then-broad',
    'verification_status = "UNVERIFIED"',
    'canonical_hash'
)

$setup = Join-Path $RuntimeRoot "setup.ps1"
Assert-Contains $setup @(
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf',
    '28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187',
    'mtp_draft_max = 2'
)
Assert-NotContains $setup @(
    '$ModelFile = "Qwen3.8-27B-Uncensored-IQ4_XS.gguf"',
    'speculative = "draft-mtp,ngram-mod"'
)

Write-Host "BLACK CODE IQ2_M FAST PROFILE STATIC VERIFY: PASS" -ForegroundColor Green
