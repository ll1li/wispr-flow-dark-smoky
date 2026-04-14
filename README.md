# Wispr Flow Dark Mode

A one-command patch that forces dark mode on [Wispr Flow](https://www.wispr.flow/) for macOS.

Wispr Flow's hub window has `background-color: white` hardcoded in the Electron renderer HTML, and the React app has no dark mode toggle. This script patches the app bundle to inject a CSS filter that inverts the UI to dark, while keeping images and media looking normal.

## Before / After

| Before | After |
|--------|-------|
| Blinding white hub window | Dark UI with inverted colors |
| White flash on every open | Dark background, no flash |

## Install

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/ll1li/wispr-flow-dark-mode/main/wispr-dark-mode -o /usr/local/bin/wispr-dark-mode
chmod +x /usr/local/bin/wispr-dark-mode
```

Or clone the repo:

```bash
git clone https://github.com/ll1li/wispr-flow-dark-mode.git
cd wispr-flow-dark-mode
cp wispr-dark-mode /usr/local/bin/
chmod +x /usr/local/bin/wispr-dark-mode
```

## Usage

```bash
# Apply dark mode
wispr-dark-mode

# Restart Wispr Flow
killall 'Wispr Flow' && open -a 'Wispr Flow'

# Restore original (if needed)
wispr-dark-mode --restore
```

## Requirements

- macOS
- [Wispr Flow](https://www.wispr.flow/) installed in `/Applications/`
- Node.js (for `npx asar` — used to unpack/repack the Electron bundle)

## How it works

1. Extracts the Electron `app.asar` bundle
2. Patches the hub and scratchpad renderer HTML files with:
   ```css
   html {
     filter: invert(0.9) hue-rotate(180deg) !important;
     background: #1a1a1a !important;
   }
   img, video, canvas, svg image, picture {
     filter: invert(1) hue-rotate(180deg) !important;
   }
   ```
3. Repacks the bundle
4. A backup is saved as `app.asar.bak` for easy restore

The CSS `invert()` + `hue-rotate()` trick flips all light colors to dark while preserving relative color relationships. Images and media get counter-inverted so they display normally.

## After Wispr Flow updates

Wispr Flow auto-updates will overwrite the patch. Just re-run:

```bash
wispr-dark-mode
killall 'Wispr Flow' && open -a 'Wispr Flow'
```

## Tested on

- Wispr Flow 1.4.822
- macOS Sonoma (Dark Mode)

## License

MIT
