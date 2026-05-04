#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
  Wispr Flow Dark-Smokey — dark theme patcher for Wispr Flow on Windows.

.DESCRIPTION
  Patches Wispr Flow's Electron app.asar bundle to inject a neutral dark theme.
  Mirrors the macOS bash script feature-for-feature with Windows-native process
  management and Squirrel install-path discovery.

.NOTES
  Set $env:WISPR_PATH to override the default install location
  ($env:LOCALAPPDATA\WisprFlow\app-X.Y.Z\).
#>

$ErrorActionPreference = 'Stop'

$Version = '1.4.0'
$Marker  = 'data-wispr-dark-smokey'
$AsarCmd = '@electron/asar@4.2.0'   # pinned — no supply-chain surprise

# ----------------------------------------------------------------------------
# Argument parsing — supports both bash-style (--restore) and PowerShell-style
# (-Restore) flags so the .cmd shim and PS-native invocation both work.
# ----------------------------------------------------------------------------

function Show-Usage {
    @"
wispr-flow-dark-smokey $Version - dark theme for Wispr Flow

Usage: wispr-flow-dark-smokey [--restore|--check|--version|--help]

  (no args)    Apply the dark theme
  --restore    Restore original Wispr Flow
  --check      Check if the theme is currently applied
  --version    Print version
  --help       Show this help

Set WISPR_PATH (env var) to override the default install location.
PowerShell-native flags (-Restore, -Check, -Version) work too.
"@
}

$Action = 'apply'

$argList = @($args)
$i = 0
while ($i -lt $argList.Count) {
    $a = [string]$argList[$i]
    switch -Regex ($a) {
        '^(-h|--help|-\?|/\?|-Help)$'              { Show-Usage; exit 0 }
        '^(--version|-Version|-v)$'                { "wispr-flow-dark-smokey $Version"; exit 0 }
        '^(--restore|-Restore)$'                   { $Action = 'restore'; $i++; continue }
        '^(--check|-Check)$'                       { $Action = 'check';   $i++; continue }
        default {
            Write-Host "Error: unknown argument '$a'" -ForegroundColor Red
            Write-Host ''
            Show-Usage
            exit 1
        }
    }
}

# ----------------------------------------------------------------------------
# Path discovery — Squirrel rotates app-X.Y.Z directories on every auto-update,
# so resolve the latest one at runtime instead of caching it. There is a small
# race window: if Wispr Flow auto-updates between our path resolution and the
# atomic mv, we'd patch the OLD versioned dir while a NEW one is now active.
# Acceptable — user just re-runs after the update completes.
# ----------------------------------------------------------------------------

function Get-WisprAsarPath {
    $rootCandidates = @()
    if ($env:WISPR_PATH) {
        $rootCandidates += $env:WISPR_PATH
    }
    else {
        $rootCandidates += (Join-Path $env:LOCALAPPDATA 'WisprFlow')
    }

    foreach ($root in $rootCandidates) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        # Form 1: $root points directly at app-X.Y.Z\
        $direct = Join-Path $root 'resources\app.asar'
        if (Test-Path -LiteralPath $direct) { return $direct }

        # Form 2: $root points at WisprFlow\ (Squirrel root) — find latest app-*
        $versioned = Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { [pscustomobject]@{ Dir = $_; Ver = [version]($_.Name -replace '^app-','') } }
                catch { $null }
            } |
            Where-Object { $_ } |
            Sort-Object Ver |
            Select-Object -Last 1

        if ($versioned) {
            $candidate = Join-Path $versioned.Dir.FullName 'resources\app.asar'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }

    return $null
}

function Get-WisprLauncher {
    # The Squirrel stub at WisprFlow\Wispr Flow.exe always launches the latest version.
    if ($env:WISPR_PATH) {
        $stub = Join-Path $env:WISPR_PATH 'Wispr Flow.exe'
        if (Test-Path -LiteralPath $stub) { return $stub }
        # Walk up if WISPR_PATH was an app-X.Y.Z dir
        $parent = Split-Path -Parent $env:WISPR_PATH
        $stub = Join-Path $parent 'Wispr Flow.exe'
        if (Test-Path -LiteralPath $stub) { return $stub }
    }
    $stub = Join-Path $env:LOCALAPPDATA 'WisprFlow\Wispr Flow.exe'
    if (Test-Path -LiteralPath $stub) { return $stub }
    return $null
}

# ----------------------------------------------------------------------------
# Process management — Electron spawns 10+ processes (main + GPU + renderer +
# helpers) all named "Wispr Flow". Wildcard catches them all in one pass.
# ----------------------------------------------------------------------------

function Test-WisprRunning {
    $procs = @()
    $procs += Get-Process -Name 'Wispr Flow'        -ErrorAction SilentlyContinue
    $procs += Get-Process -Name 'Wispr Flow Helper*' -ErrorAction SilentlyContinue
    return ($procs.Count -gt 0)
}

function Stop-WisprFlow {
    Get-Process -Name 'Wispr Flow'        -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name 'Wispr Flow Helper*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # 10-second budget — slow machines can lag releasing handles after Stop-Process
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Test-WisprRunning)) { return }
        Start-Sleep -Milliseconds 500
    }
}

function Start-WisprFlow {
    $launcher = Get-WisprLauncher
    if ($launcher) {
        try { Start-Process -FilePath $launcher -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

$asarPath = Get-WisprAsarPath
if (-not $asarPath) {
    $hint = if ($env:WISPR_PATH) { "(WISPR_PATH=$env:WISPR_PATH)" } else { "(default: $env:LOCALAPPDATA\WisprFlow)" }
    Write-Host "Error: Wispr Flow not found $hint" -ForegroundColor Red
    Write-Host "Install Wispr Flow from https://wispr.com/, or set WISPR_PATH to a custom location." -ForegroundColor Yellow
    exit 1
}

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Node.js required (npx not found). Install: https://nodejs.org" -ForegroundColor Red
    exit 1
}

$unpacked       = "$asarPath.unpacked"
$backup         = "$asarPath.bak"
$backupUnpacked = "$backup.unpacked"
$asarDir        = Split-Path -Parent $asarPath

$appWasRunning = Test-WisprRunning
$asarWritten   = $false
$tmpFile       = $null
$workDir       = $null

# ----------------------------------------------------------------------------
# --check: fast path, no extract — search asar bytes directly. The asar format
# stores HTML uncompressed, so the marker is searchable as a literal substring
# inside the binary. ~100x faster than extracting 115 MB to grep one HTML file.
# ----------------------------------------------------------------------------
if ($Action -eq 'check') {
    try {
        # Codepage 28591 = ISO-8859-1 (Latin1). Round-trip-safe for binary->string
        # mapping; portable across .NET Framework (PS 5.1) and .NET 6+ (PS 7+).
        $bytes = [System.IO.File]::ReadAllText($asarPath, [System.Text.Encoding]::GetEncoding(28591))
        if ($bytes.Contains($Marker)) {
            "Dark Smokey is applied."
        }
        else {
            "Dark Smokey is not applied."
        }
    }
    catch {
        Write-Host "Error reading asar: $_" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# ----------------------------------------------------------------------------
# Cleanup trap — runs on success, failure, or Ctrl-C. Mirrors bash trap EXIT.
# ----------------------------------------------------------------------------
try {
    if ($appWasRunning) {
        Stop-WisprFlow
    }

    # ------------------------------------------------------------------------
    # --restore
    # ------------------------------------------------------------------------
    if ($Action -eq 'restore') {
        if (-not (Test-Path -LiteralPath $backup)) {
            Write-Host "No backup found." -ForegroundColor Red
            exit 1
        }
        Move-Item -LiteralPath $backup -Destination $asarPath -Force

        if (Test-Path -LiteralPath $backupUnpacked) {
            $unpackedTmp = "$unpacked.restoring.$PID"
            if (Test-Path -LiteralPath $unpacked) {
                try { Move-Item -LiteralPath $unpacked -Destination $unpackedTmp -Force } catch {}
            }
            try {
                Move-Item -LiteralPath $backupUnpacked -Destination $unpacked -Force
                if (Test-Path -LiteralPath $unpackedTmp) {
                    Remove-Item -LiteralPath $unpackedTmp -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                if (Test-Path -LiteralPath $unpackedTmp) {
                    Move-Item -LiteralPath $unpackedTmp -Destination $unpacked -Force -ErrorAction SilentlyContinue
                }
                Write-Host "Error: failed to restore $unpacked - original left intact." -ForegroundColor Red
                exit 1
            }
        }

        $asarWritten = $true
        Write-Host "Restored. Wispr Flow will restart."
        exit 0
    }

    # ------------------------------------------------------------------------
    # Apply theme
    # ------------------------------------------------------------------------

    # Backup (first run only) - must include .unpacked dir for native binaries
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $asarPath -Destination $backup
        if (Test-Path -LiteralPath $unpacked) {
            Copy-Item -LiteralPath $unpacked -Destination $backupUnpacked -Recurse
        }
    }

    # Working directory for extract/repack
    $workDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("wispr-dark-" + [Guid]::NewGuid().ToString('N'))) -Force
    $extractDir = Join-Path $workDir 'wispr'
    $patchedAsar = Join-Path $workDir 'patched.asar'

    Write-Host "==> Extracting..."
    & npx --yes $AsarCmd extract $backup $extractDir
    if ($LASTEXITCODE -ne 0) { throw "asar extract failed (exit $LASTEXITCODE)" }

    # ------------------------------------------------------------------------
    # CSS payloads (single line each — sed strip pattern uses .* which doesn't
    # span newlines, so multi-line CSS would break idempotent strip-and-repatch)
    # ------------------------------------------------------------------------

    $darkCss   = '<style data-wispr-dark-smokey>html{background:#15131a!important;filter:invert(.91) hue-rotate(180deg) brightness(.93)!important;-webkit-font-smoothing:antialiased!important}body{background:#15131a!important}img,video,canvas,svg image,picture>img{filter:invert(1) hue-rotate(180deg)!important}:root{--sand-50:#fff!important;--sand-100:#fefefe!important;--sand-200:#fdfdfc!important;--sand-300:#fcfcfb!important;--sand-400:#fbfbfa!important;--sand-500:#fafaf9!important;--vast-50:#fefefe!important;--vast-100:#fdfdfc!important;--neutral-10:#fff!important}*:focus-visible{outline:2px solid rgba(100,149,237,.6)!important;outline-offset:2px!important}::-webkit-scrollbar{width:5px;height:5px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:rgba(128,128,128,.22);border-radius:3px}::-webkit-scrollbar-thumb:hover{background:rgba(128,128,128,.5)}::-webkit-scrollbar-thumb:active{background:rgba(128,128,128,.7)}::selection{background:rgba(120,130,170,.35)!important;color:inherit!important}</style>'

    $statusCss = '<style data-wispr-dark-smokey>html,body{background:transparent!important}*{border-color:transparent!important;box-shadow:none!important}</style>'

    # ------------------------------------------------------------------------
    # Patch each renderer's index.html. Strip pattern matches both legacy bare
    # markers AND any attribute-bearing markers from intermediate v1.4.x
    # installs, so upgrades from any v1.x are clean.
    # ------------------------------------------------------------------------

    $stripRegex = "<style $Marker[^>]*>.*?</style>"
    $utf8NoBom  = [System.Text.UTF8Encoding]::new($false)

    foreach ($renderer in @('hub','scratchpad','contextMenu')) {
        $target = Join-Path $extractDir ".webpack\renderer\$renderer\index.html"
        if (-not (Test-Path -LiteralPath $target)) {
            throw "$renderer not found at $target - Wispr Flow may have updated its structure."
        }

        $content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

        if ($content.Contains($Marker)) {
            Write-Host "==> Stripping old patch from $renderer..."
            $content = [regex]::Replace($content, $stripRegex, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        }

        Write-Host "==> Patching $renderer..."
        $content = $content.Replace('</head>', "$darkCss</head>")
        [System.IO.File]::WriteAllText($target, $content, $utf8NoBom)

        if (-not $content.Contains($Marker)) {
            throw "failed to inject CSS into $renderer - </head> not found in $target"
        }
    }

    # Status bar: separate, invert-free stylesheet
    $statusTarget = Join-Path $extractDir '.webpack\renderer\status\index.html'
    if (Test-Path -LiteralPath $statusTarget) {
        $content = [System.IO.File]::ReadAllText($statusTarget, [System.Text.Encoding]::UTF8)
        if ($content.Contains($Marker)) {
            $content = [regex]::Replace($content, $stripRegex, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        }
        Write-Host "==> Patching status..."
        $content = $content.Replace('</head>', "$statusCss</head>")
        [System.IO.File]::WriteAllText($statusTarget, $content, $utf8NoBom)

        if (-not $content.Contains($Marker)) {
            throw "failed to inject CSS into status - </head> not found in $statusTarget"
        }
    }

    # ------------------------------------------------------------------------
    # Repack and atomic rename. Temp file lives in the same NTFS volume as the
    # asar so Move-Item is atomic. Verify temp size matches packed size before
    # mv — catches truncated copies on disk-pressure conditions.
    # ------------------------------------------------------------------------
    Write-Host "==> Repacking..."
    & npx --yes $AsarCmd pack $extractDir $patchedAsar
    if ($LASTEXITCODE -ne 0) { throw "asar pack failed (exit $LASTEXITCODE)" }

    $packedSize = (Get-Item -LiteralPath $patchedAsar).Length
    if ($packedSize -le 0) { throw "asar pack produced empty file" }

    $tmpFile = Join-Path $asarDir (".app.asar.tmp." + [Guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $patchedAsar -Destination $tmpFile -Force

    $tmpSize = (Get-Item -LiteralPath $tmpFile).Length
    if ($tmpSize -ne $packedSize) {
        throw "temp file copy truncated ($tmpSize / $packedSize bytes) - is the disk full?"
    }

    # Retry Move-Item briefly in case Windows hasn't released the asar handle yet
    $moved = $false
    for ($i = 0; $i -lt 10; $i++) {
        try {
            Move-Item -LiteralPath $tmpFile -Destination $asarPath -Force
            $moved = $true
            break
        }
        catch {
            Start-Sleep -Milliseconds 400
        }
    }
    if (-not $moved) { throw "could not replace $asarPath - is Wispr Flow still running?" }

    $tmpFile = $null   # consumed by Move-Item; prevent finally from rm'ing it
    $asarWritten = $true

    Write-Host "Done. Wispr Flow Dark-Smokey applied." -ForegroundColor Green
}
finally {
    if ($workDir -and (Test-Path -LiteralPath $workDir)) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($tmpFile -and (Test-Path -LiteralPath $tmpFile)) {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
    if ($asarWritten -or $appWasRunning) {
        Start-WisprFlow
    }
}
