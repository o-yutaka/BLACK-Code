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
    $BuildVenv = $null

    if (-not (Test-Path $Manifest)) {
        throw "Package is incomplete: pet.json is missing."
    }

    if (-not (Test-Path $Sprite)) {
        $Py = if (Get-Command py -ErrorAction SilentlyContinue) { "py" }
              elseif (Get-Command python -ErrorAction SilentlyContinue) { "python" }
              else { throw "Python 3 is required to build the sprite atlas." }

        $BuildVenv = Join-Path ([IO.Path]::GetTempPath()) ("black-sentinel-" + [guid]::NewGuid())
        if ($Py -eq "py") {
            & py -3 -m venv $BuildVenv
        } else {
            & python -m venv $BuildVenv
        }
        if ($LASTEXITCODE -ne 0) { throw "Failed to create the temporary build environment." }

        $VenvPython = Join-Path $BuildVenv "Scripts\python.exe"
        & $VenvPython -m pip install --disable-pip-version-check -r (Join-Path $ScriptDir "requirements.txt")
        if ($LASTEXITCODE -ne 0) { throw "Failed to install the pinned image dependency." }

        & $VenvPython (Join-Path $ScriptDir "generate_spritesheet.py")
        if ($LASTEXITCODE -ne 0) { throw "Sprite atlas generation failed." }
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
finally {
    if ($BuildVenv -and (Test-Path $BuildVenv)) {
        Remove-Item -Recurse -Force $BuildVenv -ErrorAction SilentlyContinue
    }
}
