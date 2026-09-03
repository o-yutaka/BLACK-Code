Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallBase = Join-Path $env:LOCALAPPDATA "BLACK-Code"
$RuntimeDir = Join-Path $InstallBase "runtime"
$Server = Join-Path $RuntimeDir "llama\llama-server.exe"
$Model = Join-Path $RuntimeDir "models\Qwen3.8-27B-Uncensored-IQ2_M.gguf"
$ExpectedSha = "28e0f88eea09438220a086c2a1e5180ad83764c748856a28fd63ce1c0fbef187"

Write-Host "=== BLACK CODE IQ2_M DOCTOR ===" -ForegroundColor Cyan

Write-Host "`n[NVIDIA]"
if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) {
    & nvidia-smi.exe --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader
} else { Write-Host "FAIL: nvidia-smi.exe not found" -ForegroundColor Red }

Write-Host "`n[RAM]"
$ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
Write-Host ("{0:N1} GiB" -f $ram)

Write-Host "`n[llama.cpp]"
if (Test-Path $Server) { & $Server --version } else { Write-Host "FAIL: llama-server.exe missing" -ForegroundColor Red }

Write-Host "`n[Model]"
if (Test-Path $Model) {
    $size = (Get-Item $Model).Length / 1GB
    $hash = (Get-FileHash -Algorithm SHA256 -Path $Model).Hash.ToLowerInvariant()
    Write-Host ("{0:N2} GiB" -f $size)
    Write-Host "SHA256: $hash"
    if ($hash -eq $ExpectedSha) { Write-Host "IQ2_M HASH VERIFIED" -ForegroundColor Green }
    else { Write-Host "FAIL: IQ2_M hash mismatch" -ForegroundColor Red }
} else { Write-Host "FAIL: IQ2_M model missing" -ForegroundColor Red }

Write-Host "`n[OpenCode]"
$oc = Get-Command opencode -ErrorAction SilentlyContinue
if ($oc) { & $oc.Source --version } else { Write-Host "FAIL: opencode missing" -ForegroundColor Red }
