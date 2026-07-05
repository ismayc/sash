#!/bin/bash
# Build Sash.app and package it into a distributable, compressed .dmg with a drag-to-install
# "Applications" shortcut. Output: build/Sash.dmg
#
# Note: without an Apple Developer ID + notarization, Gatekeeper will warn on other machines.
# See the README "Installing from the DMG" note for the right-click-Open / quarantine workaround.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Sash.app"
DMG="$ROOT/build/Sash.dmg"
STAGING="$ROOT/build/dmg-staging"
VOLNAME="Sash"

# Build (and sign) the app first.
"$ROOT/scripts/build_app.sh" "$CONFIG"

echo "▶ Staging DMG contents…"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
# Drag-to-install shortcut.
ln -s /Applications "$STAGING/Applications"

echo "▶ Creating compressed disk image…"
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

rm -rf "$STAGING"

SIZE="$(du -h "$DMG" | cut -f1)"
echo "✓ Built $DMG ($SIZE)"
echo "  Open it, then drag Sash onto the Applications folder."
