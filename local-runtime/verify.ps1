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
    (Join-Path $RuntimeRoot "doctor.ps1"),
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
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf',
    'Qwen3.8-27B Uncensored IQ2_M',
    'Get-BlackCodeTrackedFileCount',
    '$trackedFileCount -le 150',
    '$Context = 8192',
    '$trackedFileCount -le 800',
    '$Context = 12288',
    '$Context = 16384',
    '$OutputLimit = 4096',
    '$OutputLimit = 6144',
    '$OutputLimit = 8192',
    '"--spec-type", "draft-mtp"',
    '"--spec-draft-n-max", "2"',
    '"--fit-ctx", "$Context"',
    'IQ2_M 10.6 GB speed/memory profile',
    'MTP max 2 ALWAYS ON',
    'explicit split OFF',
    'New-BlackCodeExecutionProfile',
    'Write-BlackCodeSessionEvidence'
)
Assert-NotContains $launcher @(
    '$ModelFile = "Qwen3.8-27B-Uncensored-IQ4_XS.gguf"',
    '"--spec-type", "draft-mtp,ngram-mod"',
    '"--spec-ngram-mod-n-match"',
    '"--cache-reuse"',
    '"--tensor-split"',
    '"-ts"'
)

$fabric = Join-Path $RuntimeRoot "execution-fabric.ps1"
Assert-Contains $fabric @(
    'black-execution-fabric-iq2m-speed-v1',
    'decode.iq2m-mtp2',
    'quantization = "IQ2_M"',
    'mtp_draft_max = 2',
    'rejected_atoms',
    'decode.ngram-mod',
    'prompt.cache-reuse-256',
    'verification_status = "UNVERIFIED"',
    'canonical_hash'
)

$instructions = Join-Path $RuntimeRoot "black-code-execution.md"
Assert-Contains $instructions @(
    'FIRST PASS BATCH',
    'DELTA CONTEXT',
    'PREFETCH + BATCH',
    'AFFECTED VERIFY',
    'MINIMIZE MODEL CALLS',
    'avoid progress chatter'
)

$setup = Join-Path $RuntimeRoot "setup.ps1"
Assert-Contains $setup @(
    '$ModelFile = "Qwen3.8-27B-Uncensored-IQ2_M.gguf"',
    '28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187',
    '$LegacyModelPath = Join-Path $ModelDir "Qwen3.8-27B-Uncensored-IQ4_XS.gguf"',
    'Removed superseded IQ4_XS model file.',
    'default_context = 16384',
    'mtp_draft_max = 2',
    '"verify.ps1"'
)
Assert-NotContains $setup @(
    '$ModelFile = "Qwen3.8-27B-Uncensored-IQ4_XS.gguf"',
    'speculative = "draft-mtp,ngram-mod"'
)

$doctor = Join-Path $RuntimeRoot "doctor.ps1"
Assert-Contains $doctor @(
    'Qwen3.8-27B-Uncensored-IQ2_M.gguf',
    '28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187',
    'IQ2_M HASH VERIFIED'
)
Assert-NotContains $doctor @('Qwen3.8-27B-Uncensored-IQ4_XS.gguf')

Write-Host "BLACK CODE SPEED V2 STATIC VERIFY: PASS" -ForegroundColor Green
