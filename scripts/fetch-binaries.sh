#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/AndroidMirror/Resources/Binaries"
ARCH="$(uname -m)"

mkdir -p "$DEST"

if [[ "$ARCH" == "arm64" ]]; then
  URL="https://github.com/Genymobile/scrcpy/releases/download/v4.0/scrcpy-macos-aarch64-v4.0.tar.gz"
  DIR="scrcpy-macos-aarch64-v4.0"
else
  URL="https://github.com/Genymobile/scrcpy/releases/download/v4.0/scrcpy-macos-x86_64-v4.0.tar.gz"
  DIR="scrcpy-macos-x86_64-v4.0"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading scrcpy v4.0 for ${ARCH}..."
curl -fsSL -o "$TMP/scrcpy.tar.gz" "$URL"
tar -xzf "$TMP/scrcpy.tar.gz" -C "$TMP"

cp "$TMP/$DIR/scrcpy" "$TMP/$DIR/adb" "$TMP/$DIR/scrcpy-server" "$DEST/"
cp "$TMP/$DIR/scrcpy.png" "$TMP/$DIR/disconnected.png" "$DEST/"
chmod +x "$DEST/scrcpy" "$DEST/adb"

echo "Installed to $DEST"
ls -la "$DEST"
