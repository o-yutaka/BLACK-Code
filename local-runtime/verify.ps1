Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RuntimeRoot = $PSScriptRoot

function Assert-Contains([string]$Path, [string[]]$Needles) {
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($needle in $Needles) {
        if (-not $content.Contains($needle)) {
            throw "Missing contract '$needle' in $Path"
        }
    }
}

function Assert-NotContains([string]$Path, [string[]]$Needles) {
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($needle in $Needles) {
        if ($content.Contains($needle)) {
            throw "Rejected runtime contract '$needle' is present in $Path"
        }
    }
}

$files = @(
    (Join-Path $RuntimeRoot "black-code.ps1"),
    (Join-Path $RuntimeRoot "setup.ps1"),
    (Join-Path $RuntimeRoot "execution-fabric.ps1"),
    (Join-Path $RuntimeRoot "verify.ps1")
)

foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Required runtime file is missing: $file"
    }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file,
        [ref]$tokens,
        [ref]$parseErrors
    )
    $errorList = @($parseErrors)
    if ($errorList.Count -gt 0) {
        foreach ($parseError in $errorList) {
            Write-Host ("{0}:{1}:{2}: {3} :: {4}" -f `
                $file,
                $parseError.Extent.StartLineNumber,
                $parseError.Extent.StartColumnNumber,
                $parseError.Message,
                $parseError.Extent.Text)
        }
        throw "PowerShell parse failed: $file"
    }
}

$launcher = Join-Path $RuntimeRoot "black-code.ps1"
Assert-Contains $launcher @(
    '"--spec-type", "draft-mtp"',
    '--spec-draft-n-max',
    '"4"',
    'black-code-execution.md',
    'New-BlackCodeExecutionProfile',
    'Write-BlackCodeSessionEvidence',
    'MTP max 4 ALWAYS ON (measured-fast)',
    'N-gram:    OFF by default',
    'forced cache-reuse OFF'
)
Assert-NotContains $launcher @(
    '"--spec-type", "draft-mtp,ngram-mod"',
    '"--spec-ngram-mod-n-match"',
    '"--cache-reuse"'
)

$fabric = Join-Path $RuntimeRoot "execution-fabric.ps1"
Assert-Contains $fabric @(
    'black-execution-fabric-measured-fast-v1',
    'task.atomize',
    'work.dedupe-overlap',
    'context.reuse-session',
    'tool.prefetch-batch',
    'decode.mtp4',
    'rejected_atoms',
    'decode.ngram-mod',
    'prompt.cache-reuse-256',
    'reject_regressing_atoms = $true',
    'verification_status = "UNVERIFIED"',
    'canonical_hash'
)

$instructions = Join-Path $RuntimeRoot "black-code-execution.md"
Assert-Contains $instructions @(
    'ATOMIZE',
    'DEDUPE',
    'REUSE',
    'PREFETCH + BATCH',
    'RECOMPOSE',
    'TARGET VERIFY',
    'EVIDENCE',
    'MINIMIZE MODEL CALLS'
)

$setup = Join-Path $RuntimeRoot "setup.ps1"
Assert-Contains $setup @(
    'execution-fabric.ps1',
    'black-code-execution.md',
    'mtp_draft_max = 4'
)

Write-Host "BLACK CODE MEASURED-FAST EXECUTION FABRIC STATIC VERIFY: PASS" -ForegroundColor Green
