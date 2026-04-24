#!/usr/bin/env bash
# Build a DMG from an existing Cairn.app bundle.
# Requires `brew install create-dmg`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_PATH="${1:-}"
OUT_DMG="${2:-}"
[ -d "$APP_PATH" ] && [ -n "$OUT_DMG" ] || {
    echo "usage: $0 <path/to/Cairn.app> <output.dmg>" >&2
    exit 1
}

command -v create-dmg >/dev/null 2>&1 || {
    echo "error: create-dmg not found. Install via: brew install create-dmg"
    exit 1
}

mkdir -p "$(dirname "$OUT_DMG")"
rm -f "$OUT_DMG"

VERSION_LABEL="$(basename "$OUT_DMG" .dmg | sed 's/^Cairn-//')"

echo "Creating $OUT_DMG..."
create-dmg \
    --volname "Cairn $VERSION_LABEL" \
    --window-size 500 340 \
    --icon-size 96 \
    --app-drop-link 380 160 \
    --icon "Cairn.app" 120 160 \
    "$OUT_DMG" \
    "$APP_PATH"

echo "$OUT_DMG ready ($(du -h "$OUT_DMG" | cut -f1))"
