param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0

$Guard = Join-Path $PSScriptRoot "assert-native-windows.ps1"
$Runtime = Join-Path $PSScriptRoot "black-code.ps1"
foreach ($required in @($Guard,$Runtime)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required native BLACK Code launcher input missing: $required" }
}

. $Guard -Quiet
& $Runtime @Arguments
exit $LASTEXITCODE
