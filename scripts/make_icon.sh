#!/bin/bash
# Generate Resources/AppIcon.icns from the CoreGraphics renderer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/build/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$ROOT/Resources"
swift "$ROOT/scripts/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "✓ Wrote $OUT"
