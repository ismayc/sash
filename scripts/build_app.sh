#!/bin/bash
# Build Sash and wrap the SwiftPM binary in a proper .app bundle, then sign it.
# Uses the stable "Sash Self-Signed" identity if present (so the Accessibility grant
# persists across rebuilds — see scripts/make_cert.sh); otherwise falls back to ad-hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Sash.app"
IDENTITY="Sash Self-Signed"

echo "▶ Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT" --product Sash
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/Sash"

# Ensure the icon exists.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "▶ Generating app icon…"
    "$ROOT/scripts/make_icon.sh"
fi

echo "▶ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sash"
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "▶ Signing with stable identity “$IDENTITY”…"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "▶ Signing ad-hoc (run scripts/make_cert.sh once to make the Accessibility grant stick)…"
    codesign --force --deep --sign - "$APP"
fi

echo "✓ Built $APP"
echo "  Launch:  open \"$APP\""
