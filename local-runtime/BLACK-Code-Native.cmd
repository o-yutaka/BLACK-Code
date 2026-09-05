@echo off
setlocal EnableExtensions

if defined WSL_INTEROP (
  echo ERROR: WSL interop detected. BLACK Code canonical runtime is native Windows only.
  echo Open Windows PowerShell or CMD directly and run this file there.
  exit /b 2
)
if defined WSL_DISTRO_NAME (
  echo ERROR: WSL environment detected. BLACK Code canonical runtime is native Windows only.
  echo Open Windows PowerShell or CMD directly and run this file there.
  exit /b 2
)

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo ERROR: Native Windows PowerShell not found: %PS%
  exit /b 2
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0assert-native-windows.ps1" -Quiet
if errorlevel 1 exit /b %errorlevel%

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-resumable-7.27.ps1" %*
exit /b %errorlevel%
