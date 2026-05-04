# Wispr Flow Dark-Smokey

## What This Is
Cross-platform CSS-injection patcher for Wispr Flow's Electron `app.asar` bundle.
- macOS: bash script (`wispr-flow-dark-smokey`)
- Windows: PowerShell script (`wispr-flow-dark-smokey.ps1`) + cmd shim (`wispr-flow-dark-smokey.cmd`)

No build system, no dependencies beyond Node.js (`npx @electron/asar`). Single theme, no variants — earlier v1.4.x experiments with multiple themes (smokey/dune/midnight/forest/eclipse/wine) were stripped because the visible difference between filter-based variants was too subtle to justify the surface area.

## Naming
- Display name: "Wispr Flow Dark-Smokey"
- Code/path name: `wispr-flow-dark-smokey`
- CLI command (both platforms): `wispr-flow-dark-smokey`
- CSS marker: `data-wispr-dark-smokey` (bare, no attribute)
- GitHub repo: `ll1li/wispr-flow-dark-smokey`

## Project Layout
- `wispr-flow-dark-smokey` — macOS bash script (v1.4.0)
- `wispr-flow-dark-smokey.ps1` — Windows PowerShell port (v1.4.0). Feature parity with bash.
- `wispr-flow-dark-smokey.cmd` — Windows cmd.exe shim that forwards args to pwsh/powershell
- `install-windows.ps1` — one-shot Windows installer; drops `.ps1` + `.cmd` into `%USERPROFILE%\.local\bin\`
- `banner.png` — hero image for README
- `README.md` — cross-platform docs
- No tests, no CI — manual verification only

## Commands
```bash
wispr-flow-dark-smokey            # Apply the dark theme
wispr-flow-dark-smokey --restore  # Restore original
wispr-flow-dark-smokey --check    # Check if applied
wispr-flow-dark-smokey --version  # Print version
```

PowerShell-native flags also work on Windows: `-Restore`, `-Check`, `-Version`.

## Key Patterns (both platforms)
- Always extract from `app.asar.bak` (clean backup), never from a previously patched asar
- Backup must include `app.asar.unpacked/` dir (native binaries like Jabra connectors)
- Atomic write: temp file on same filesystem → copy → **size verification** → rename. Truncated copies are caught before the swap.
- Temp file tracked in cleanup trap (bash `trap EXIT` / PowerShell `try { } finally { }`) — removed on failure, cleared after successful rename
- App-was-running flag — restarts app even on script failure so user is never left without it
- Post-inject verification — checks for marker after injection, fails loudly if missing
- Idempotent strip-and-repatch — strip regex `<style data-wispr-dark-smokey[^>]*>.*</style>` matches both bare markers (v1.3.x) and any attribute-bearing markers from intermediate v1.4.x experiments
- Status bar renderer gets different CSS (no invert — natively dark/transparent)
- `meeting_recorder` renderer exists but intentionally not patched (transient window)
- `--check` reads asar bytes directly (no extract); ~100× faster than v1.3.x

## CSS Strategy
- `filter: invert(.91) hue-rotate(180deg) brightness(.93)` on `html` — no sepia (neutral)
- Background `#15131a` on both `html` and `body` — faint cool tint, no brown
- No animated overlay (removed in v1.3.3 — was constant GPU cost for subtle effect)
- No atmospheric body::before / grain body::after layers (removed in v1.4.0 — visible payoff didn't justify the GPU compositing cost)
- CSS variable overrides: all `--sand-*`, `--vast-*`, `--neutral-10` forced to `#fff` so they all invert to consistent depth
- Images/video/canvas counter-inverted: `filter: invert(1) hue-rotate(180deg)`
- `-webkit-font-smoothing: antialiased` prevents text bloom
- Selection color: cool slate `rgba(120,130,170,.35)` matching neutral dark aesthetic
- Focus: `rgba(100,149,237,.6)` outline, 2px offset
- Scrollbar: 5px width, hover + active states

## Dependencies
- `@electron/asar@4.2.0` (pinned, not the deprecated `asar` package)
- Node.js (any version with npx)
- macOS or Windows 10/11

## Process Management

### macOS
- `pgrep -f` (not `-x`) catches all Electron helper processes (GPU, Renderer, Plugin)
- `killall 'Wispr Flow'` sends SIGTERM cascading to all children
- Restart via `open -a 'Wispr Flow'`

### Windows
- `Get-Process -Name 'Wispr Flow'` matches the main process AND all subprocess instances (Electron creates many with the same .exe name)
- `Get-Process -Name 'Wispr Flow Helper*'` covers the Helper / GPU / Renderer / Plugin variants
- Restart via the Squirrel stub: `%LOCALAPPDATA%\WisprFlow\Wispr Flow.exe` (always points at the current version)
- 10-second post-kill wait budget — slow machines can lag releasing handles after Stop-Process
- 10-attempt retry on `Move-Item -Force` (400 ms each) for the same reason

## Windows install layout (Squirrel)
- Install root: `%LOCALAPPDATA%\WisprFlow\`
- Versioned dirs: `app-X.Y.Z\` — Squirrel keeps previous versions for rollback
- Asar: `<install-root>\app-X.Y.Z\resources\app.asar`
- **Auto-updates create a NEW versioned directory** — the patched asar in the old `app-X.Y.Z\` becomes orphaned. The script always resolves the latest `app-*` dir at runtime, so the user just re-runs after updates.
- **Auto-update race window:** if Squirrel updates between path resolution and atomic mv, the patch lands on the previous versioned dir while a new one is now active. Acceptable trade-off — user re-runs once. Documented in README.
- `WISPR_PATH` env var override: can point at the WisprFlow root, an `app-X.Y.Z` directory directly, or any dir containing a `resources\app.asar`

## macOS security
- Replacing `app.asar` invalidates codesign sealed resources — expected and safe
- Gatekeeper does not re-check previously approved apps
- No ASAR integrity checking in current Wispr Flow (no `ElectronAsarIntegrity` in Info.plist)
- If future Wispr Flow adds integrity checking, patch will fail at startup — check Info.plist

## Edge cases handled
- **Disk full during temp copy** — explicit byte-size verification between source and tmpfile before atomic mv. Truncated copies abort the run; original asar untouched.
- **Wispr Flow file lock lag** (Windows) — 10-attempt × 400 ms retry on Move-Item. Almost always resolves within 1-2 attempts.
- **User runs without backup, then `--restore`** — clean error: "No backup found."
- **Stale `.bak` from a previously patched run** — irrelevant; we always extract from `.bak` and the patched HTML inside is stripped by the marker regex before re-injecting.
- **Concurrent script runs** — no lock, but the atomic mv is the only mutation point. Two simultaneous runs would race at the rename and one would see "file in use" via the retry loop. No corruption possible.
- **Marker upgrade path** — strip regex `data-wispr-dark-smokey[^>]*` matches v1.3.x bare markers AND v1.4.x experimental theme-attribute markers. Anyone upgrading sees a clean re-patch.
- **Wispr Flow renderer path changes** — script errors out per-renderer with a specific message, doesn't silently fail.

## Testing
- Manual only: run `wispr-flow-dark-smokey`, visually verify in Wispr Flow
- Test `--restore`, `--check` flags
- Test unknown-arg path: should error and show usage
- Test `--check` against unpatched and patched asar (correct yes/no)
- Check modals/dialogs/popups have dark overlay (not bleached white wash)
- Verify media (images/video) render correctly (counter-invert)
- After Wispr Flow updates: check renderer paths still exist (`hub`, `scratchpad`, `contextMenu`, `status`)
- On Windows after auto-update: confirm new `app-X.Y.Z` dir is detected by re-running

## Gotchas
- Wispr Flow auto-updates overwrite the patch (Mac) or orphan it in the previous `app-X.Y.Z` dir (Windows) — re-run after updates
- Stale `.bak` without matching `.bak.unpacked/` dir will crash `asar extract`
- macOS sed strip pattern uses `.*` — CSS must not span multiple lines (it doesn't, but watch out when editing the template)
- The `--restore` flow does atomic swap of `.unpacked` dir to prevent data loss
- PowerShell PSScriptAnalyzer would flag heredoc-substituted variables as "assigned but never used" — this script uses inline string literals to avoid the false positive (and it's also marginally faster: no heredoc allocation)
