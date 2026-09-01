Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallBase = Join-Path $env:LOCALAPPDATA "BLACK-Code"
$RuntimeDir = Join-Path $InstallBase "runtime"
$Server = Join-Path $RuntimeDir "llama\llama-server.exe"
$Model = Join-Path $RuntimeDir "models\Qwen3.8-27B-Uncensored-IQ4_XS.gguf"

Write-Host "=== BLACK CODE LOCAL DOCTOR ===" -ForegroundColor Cyan

Write-Host "`n[NVIDIA]"
if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) {
    & nvidia-smi.exe --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader
} else {
    Write-Host "FAIL: nvidia-smi.exe not found" -ForegroundColor Red
}

Write-Host "`n[RAM]"
$ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
Write-Host ("{0:N1} GiB" -f $ram)

Write-Host "`n[llama.cpp]"
if (Test-Path $Server) {
    & $Server --version
} else {
    Write-Host "FAIL: llama-server.exe missing" -ForegroundColor Red
}

Write-Host "`n[Model]"
if (Test-Path $Model) {
    $size = (Get-Item $Model).Length / 1GB
    $hash = (Get-FileHash -Algorithm SHA256 -Path $Model).Hash.ToLowerInvariant()
    Write-Host ("{0:N2} GiB" -f $size)
    Write-Host "SHA256: $hash"
} else {
    Write-Host "FAIL: model missing" -ForegroundColor Red
}

Write-Host "`n[OpenCode]"
$oc = Get-Command opencode -ErrorAction SilentlyContinue
if ($oc) {
    & $oc.Source --version
} else {
    Write-Host "FAIL: opencode missing" -ForegroundColor Red
}
