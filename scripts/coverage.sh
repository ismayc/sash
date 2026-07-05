#!/bin/bash
# Build the test runner with coverage instrumentation, run it, and report line coverage
# for the SashKit (pure-logic) target.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
COVDIR="$ROOT/.build/coverage"
mkdir -p "$COVDIR"

FLAGS=(-Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping)

echo "▶ Building test runner with coverage…"
swift build --product SashTests "${FLAGS[@]}" >/dev/null
BIN="$(swift build --product SashTests "${FLAGS[@]}" --show-bin-path)/SashTests"

echo "▶ Running tests…"
LLVM_PROFILE_FILE="$COVDIR/tests.profraw" "$BIN"

echo "▶ Merging coverage…"
xcrun llvm-profdata merge -sparse "$COVDIR/tests.profraw" -o "$COVDIR/tests.profdata"

echo
echo "▶ Coverage for SashKit:"
xcrun llvm-cov report "$BIN" \
    -instr-profile="$COVDIR/tests.profdata" \
    -ignore-filename-regex='(Tests|\.build)/' \
    Sources/SashKit
