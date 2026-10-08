@echo off
rem build.cmd - launcher for build.ps1.
rem Prefer PowerShell 7 when available; Windows PowerShell is the fallback.
rem The execution policy is bypassed for this invocation only, so the
rem script is not blocked by the machine or user execution policy.
rem See the LICENSE file at the top of the project tree for copyright
rem and license details.
setlocal EnableExtensions DisableDelayedExpansion
where pwsh.exe >nul 2>&1
if errorlevel 1 goto windows_powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0%~n0.ps1" %*
exit /b %ERRORLEVEL%
:windows_powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0%~n0.ps1" %*
exit /b %ERRORLEVEL%
