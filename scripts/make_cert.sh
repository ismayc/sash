#!/bin/bash
# Create a stable, self-signed code-signing identity in the login keychain.
#
# Why: an ad-hoc signature (`codesign -s -`) changes every rebuild, so macOS forgets the
# Accessibility permission each time. Signing with a *stable* identity gives the app a
# consistent designated requirement, so you grant Accessibility once and it sticks across
# rebuilds. This is a local dev cert — not an Apple Developer ID (which would also enable
# distribution/notarization).
#
# Run this ONCE. build_app.sh then signs with it automatically if present.
set -euo pipefail

IDENTITY="Sash Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$IDENTITY"; then
    echo "✓ Identity “$IDENTITY” already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▶ Generating key + self-signed code-signing certificate…"
openssl genrsa -out "$TMP/key.pem" 2048 >/dev/null 2>&1
openssl req -new -x509 -key "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass: -name "$IDENTITY" >/dev/null 2>&1

echo "▶ Importing into the login keychain (allowing codesign to use it)…"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "" -T /usr/bin/codesign -A

echo "▶ Trusting the certificate for code signing (may prompt for your login password)…"
# Trust so codesign accepts it as a valid signing identity.
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k /Library/Keychains/System.keychain "$TMP/cert.pem" 2>/dev/null || \
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" || true

echo
echo "✓ Created identity “$IDENTITY”."
echo "  Rebuild with ./scripts/build_app.sh — it will sign with this identity automatically."
echo "  Grant Accessibility once more after the first signed build; it will then persist."
