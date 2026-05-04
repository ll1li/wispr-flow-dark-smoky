@echo off
rem Command shim for invoking the PowerShell script from cmd.exe or other PATH-aware launchers.
rem Forwards all arguments to wispr-flow-dark-smokey.ps1.
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%wispr-flow-dark-smokey.ps1"

rem Prefer PowerShell 7+ (pwsh); fall back to Windows PowerShell 5.1.
where /q pwsh.exe
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
)
exit /b %ERRORLEVEL%
