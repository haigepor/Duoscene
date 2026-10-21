@echo off
setlocal
set "PWSH=pwsh.exe"
where pwsh.exe >nul 2>nul
if errorlevel 1 set "PWSH=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-lan.ps1" %*
exit /b %errorlevel%
