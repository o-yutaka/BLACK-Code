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
    'draft-mtp,ngram-mod',
    '--spec-draft-n-max',
    '"4"',
    '--spec-ngram-mod-n-match',
    '--cache-reuse',
    'black-code-execution.md',
    'New-BlackCodeExecutionProfile',
    'Write-BlackCodeSessionEvidence'
)

$fabric = Join-Path $RuntimeRoot "execution-fabric.ps1"
Assert-Contains $fabric @(
    'black-execution-fabric-v1',
    'task.atomize',
    'work.dedupe-overlap',
    'context.reuse-session',
    'tool.prefetch-batch',
    'verify.targeted-then-broad',
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
    'execution_fabric = "black-execution-fabric-v1"',
    'mtp_draft_max = 4'
)

Write-Host "BLACK CODE EXECUTION FABRIC STATIC VERIFY: PASS" -ForegroundColor Green
