#!/usr/bin/env bash
# Build an unsigned DMG of Cairn for local testing.
# Requires `brew install create-dmg`.
# Distribution-ready (notarized, signed) DMG is Phase 3.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

command -v create-dmg >/dev/null 2>&1 || {
    echo "error: create-dmg not found. Install via: brew install create-dmg"
    exit 1
}

echo "▸ Building Release Cairn.app..."
./scripts/build-rust.sh
./scripts/gen-bindings.sh
(cd apps && xcodegen generate)
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Release \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    -derivedDataPath .dmg-build 2>&1 | tail -5

APP_PATH="$(find .dmg-build -name 'Cairn.app' -type d | head -1)"
if [ -z "$APP_PATH" ]; then
    echo "error: Cairn.app not found under .dmg-build/"
    exit 1
fi

OUT_DMG="Cairn-v0.1.0-alpha.dmg"
rm -f "$OUT_DMG"

echo "▸ Creating $OUT_DMG..."
create-dmg \
    --volname "Cairn v0.1.0-alpha" \
    --window-size 500 340 \
    --icon-size 96 \
    --app-drop-link 380 160 \
    --icon "Cairn.app" 120 160 \
    "$OUT_DMG" \
    "$APP_PATH"

echo "✓ $OUT_DMG ready ($(du -h "$OUT_DMG" | cut -f1))"
echo "  (unsigned — Gatekeeper will complain unless you right-click → Open)"
