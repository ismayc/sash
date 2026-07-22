#!/bin/bash
# Build Sash.app and package it into a distributable, compressed .dmg with a drag-to-install
# "Applications" shortcut. Output: build/Sash-<version>.dmg, e.g. build/Sash-0.3.0.dmg —
# the version is read back out of the app that was just built, so the filename can never
# disagree with what is inside it.
#
# Note: without an Apple Developer ID + notarization, Gatekeeper will warn on other machines.
# See the README "Installing from the DMG" note for the right-click-Open / quarantine workaround.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Sash.app"
STAGING="$ROOT/build/dmg-staging"

# Build (and sign) the app first.
"$ROOT/scripts/build_app.sh" "$CONFIG"

# Name the image after the version inside the bundle we just built, so a release artifact
# is never ambiguous about which build it is.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$ROOT/build/Sash-$VERSION.dmg"
VOLNAME="Sash $VERSION"

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
