#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="https://raw.githubusercontent.com/ll1li/wispr-flow-dark-smokey/main"
SCRIPT_NAME="wispr-flow-dark-smokey"
TARGET_DIR="/usr/local/bin"
TARGET_PATH="$TARGET_DIR/$SCRIPT_NAME"
FROM_CLONE=0

if [[ "${1:-}" == "--from-clone" ]]; then
  FROM_CLONE=1
fi

install_file() {
  local src="$1"
  local dest="$2"

  if [[ -w "$(dirname "$dest")" ]]; then
    install -m 0755 "$src" "$dest"
  else
    sudo install -m 0755 "$src" "$dest"
  fi
}

download_to_target() {
  if [[ -w "$TARGET_DIR" ]]; then
    curl -fsSL "$RAW_BASE/$SCRIPT_NAME" -o "$TARGET_PATH"
    chmod 0755 "$TARGET_PATH"
  else
    curl -fsSL "$RAW_BASE/$SCRIPT_NAME" | sudo tee "$TARGET_PATH" >/dev/null
    sudo chmod 0755 "$TARGET_PATH"
  fi
}

if [[ "$FROM_CLONE" == "1" ]]; then
  SRC="$PWD/$SCRIPT_NAME"
  [[ -f "$SRC" ]] || { echo "Error: $SRC not found. Run from inside the repo clone."; exit 1; }
  install_file "$SRC" "$TARGET_PATH"
else
  download_to_target
fi

echo
echo "Installed to: $TARGET_PATH"
echo
echo "Try it:"
echo "  wispr-flow-dark-smokey --version"
echo "  wispr-flow-dark-smokey --check"
echo "  wispr-flow-dark-smokey"
