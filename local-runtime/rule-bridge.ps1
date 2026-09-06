param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$Seen = @{}
$Blocks = New-Object System.Collections.Generic.List[string]

function Add-RuleFile([string]$Candidate, [int]$Depth = 0) {
    if ($Depth -gt 5 -or -not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { return }
    $Resolved = (Resolve-Path -LiteralPath $Candidate).Path
    $Key = $Resolved.ToLowerInvariant()
    if ($Seen.ContainsKey($Key)) { return }
    $Seen[$Key] = $true

    $Text = Get-Content -Raw -LiteralPath $Resolved -ErrorAction Stop
    if ($Text.Length -gt 12000) { $Text = $Text.Substring(0, 12000) }
    [void]$Blocks.Add("# Imported rules: $Resolved`n$Text")

    $Fenced = $false
    foreach ($Line in ($Text -split "`r?`n")) {
        if ($Line.TrimStart().StartsWith('```')) { $Fenced = -not $Fenced; continue }
        if ($Fenced) { continue }
        foreach ($Match in [regex]::Matches($Line, '(?<![\w@])@([^\s`]+)')) {
            $Raw = $Match.Groups[1].Value.TrimEnd('.', ',', ';', ':', ')', ']', '}', '>')
            if (-not $Raw) { continue }
            $Imported = if ([IO.Path]::IsPathRooted($Raw)) { $Raw } else { Join-Path (Split-Path -Parent $Resolved) $Raw }
            Add-RuleFile $Imported ($Depth + 1)
        }
    }
}

$HomeClaude = Join-Path $HOME ".claude\CLAUDE.md"
Add-RuleFile $HomeClaude

$Chain = @()
$Cursor = Get-Item -LiteralPath $Root
while ($Cursor) {
    $Chain = @($Cursor.FullName) + $Chain
    $Cursor = $Cursor.Parent
}
foreach ($Directory in $Chain) {
    if ([string]::IsNullOrWhiteSpace($Directory)) { continue }
    Add-RuleFile (Join-Path $Directory "CLAUDE.md")
    Add-RuleFile (Join-Path $Directory "CLAUDE.local.md")
}
Add-RuleFile (Join-Path $Root "BLACK.md")

$Body = if ($Blocks.Count) { $Blocks -join "`n`n" } else { "# BLACK Code Project Rules`n`nNo CLAUDE.md, CLAUDE.local.md, BLACK.md, or imported @file rules were found." }
if ($Body.Length -gt 6000) {
    $Sources = @($Blocks | ForEach-Object { if ($_ -match '^# Imported rules: (.+)$') { $Matches[1] } } | Where-Object { $_ })
    $Body = $Body.Substring(0, 6000) + "`n`n[rule bridge truncated at 6000 characters to protect the prompt budget; read the full source file(s) on demand: $([string]::Join(', ', @($Sources | Select-Object -First 25)))]"
}
$Parent = Split-Path -Parent $Destination
if ($Parent) { New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
Set-Content -Encoding UTF8 -LiteralPath $Destination -Value $Body
Write-Host "BLACK Code rule bridge: $($Seen.Count) rule file(s) -> $Destination"
