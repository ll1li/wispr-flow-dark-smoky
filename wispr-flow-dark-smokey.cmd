@echo off
rem wispr-flow-dark-smokey.cmd - cmd.exe shim that forwards all args to the PowerShell script.
rem Lets users invoke `wispr-flow-dark-smokey` with any flags from cmd or any PATH-aware launcher.
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
