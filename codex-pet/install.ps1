[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" })
)

$ErrorActionPreference = "Stop"
$ExpectedSha256 = "f7a5a2cf2d1995590720024d1738bb916fc80255dbea8be4e058fa249c6a7ed3"

try {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $Sprite = Join-Path $ScriptDir "spritesheet.png"
    $Manifest = Join-Path $ScriptDir "pet.json"

    if (-not (Test-Path $Sprite) -or -not (Test-Path $Manifest)) {
        throw "Package is incomplete. spritesheet.png and pet.json are required."
    }

    $ActualSha256 = (Get-FileHash -Algorithm SHA256 $Sprite).Hash.ToLowerInvariant()
    if ($ActualSha256 -ne $ExpectedSha256) {
        throw "Spritesheet checksum mismatch: $ActualSha256"
    }

    $Target = Join-Path $CodexHome "pets\black-sentinel"
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    Copy-Item $Sprite (Join-Path $Target "spritesheet.png") -Force
    Copy-Item $Manifest (Join-Path $Target "pet.json") -Force

    Write-Host "Installed BLACK Sentinel to $Target"
    Write-Host "Restart Codex, then select BLACK Sentinel from custom pets."
}
catch {
    Write-Error "BLACK Sentinel installation failed: $($_.Exception.Message)"
    exit 1
}
