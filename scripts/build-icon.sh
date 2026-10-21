#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
ICONSET="$TEMP_DIR/AppIcon.iconset"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Resources/AppIcon.icns"
cp "$ICONSET/icon_512x512@2x.png" "$ROOT_DIR/Resources/AppIcon-preview.png"
