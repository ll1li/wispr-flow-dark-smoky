#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
  One-shot installer for Wispr Flow Dark-Smokey on Windows.

.DESCRIPTION
  Downloads (or copies, when run from a clone) the .ps1 + .cmd into
  $env:USERPROFILE\.local\bin\, then verifies that directory is on the user PATH.

.PARAMETER FromClone
  Install from the local repo clone instead of GitHub raw URLs.
  Use when you've already cloned the repo and want to install your local copy.

.EXAMPLE
  iwr -useb https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main/install-windows.ps1 | iex

.EXAMPLE
  # From a local clone:
  ./install-windows.ps1 -FromClone
#>

[CmdletBinding()]
param(
    [switch]$FromClone
)

$ErrorActionPreference = 'Stop'

$RawBase = 'https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main'
$Files   = @('wispr-flow-dark-smokey.ps1', 'wispr-flow-dark-smokey.cmd')

$BinDir = Join-Path $env:USERPROFILE '.local\bin'
if (-not (Test-Path -LiteralPath $BinDir)) {
    Write-Host "Creating $BinDir..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

# ----------------------------------------------------------------------------
# Copy or download
# ----------------------------------------------------------------------------

foreach ($file in $Files) {
    $dest = Join-Path $BinDir $file
    if ($FromClone) {
        $src = Join-Path $PSScriptRoot $file
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "Error: $src not found. Run from inside the repo clone." -ForegroundColor Red
            exit 1
        }
        Write-Host "Copying $file -> $dest" -ForegroundColor Cyan
        Copy-Item -LiteralPath $src -Destination $dest -Force
    }
    else {
        $url = "$RawBase/$file"
        Write-Host "Downloading $file from $url" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
}

# ----------------------------------------------------------------------------
# PATH check — non-destructive: warn the user with a copy-pasteable fix.
# (We don't silently mutate PATH; that's surprising and hard to undo.)
# ----------------------------------------------------------------------------

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathParts = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
$onPath = $pathParts -contains $BinDir -or $pathParts -contains $BinDir.TrimEnd('\')

Write-Host ''
Write-Host '----------------------------------------------------------------------'
Write-Host "Installed to: $BinDir" -ForegroundColor Green
Write-Host '----------------------------------------------------------------------'

if (-not $onPath) {
    Write-Host ''
    Write-Host "  $BinDir is NOT on your user PATH yet." -ForegroundColor Yellow
    Write-Host '  Add it (one-time, persists across sessions) by running this in a NEW PowerShell window:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '      [Environment]::SetEnvironmentVariable(' -ForegroundColor Cyan -NoNewline
    Write-Host "'Path'," -ForegroundColor Cyan -NoNewline
    Write-Host ' ' -NoNewline
    Write-Host "([Environment]::GetEnvironmentVariable('Path','User') + ';$BinDir')," -ForegroundColor Cyan -NoNewline
    Write-Host ' ' -NoNewline
    Write-Host "'User'" -ForegroundColor Cyan -NoNewline
    Write-Host ')' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Then close and reopen your shell.' -ForegroundColor Yellow
}
else {
    Write-Host ''
    Write-Host "  PATH already includes $BinDir - you're good." -ForegroundColor Green
}

Write-Host ''
Write-Host 'Try it:' -ForegroundColor Cyan
Write-Host '  wispr-flow-dark-smokey --version'
Write-Host '  wispr-flow-dark-smokey --check'
Write-Host '  wispr-flow-dark-smokey'
Write-Host ''
