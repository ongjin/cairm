#!/usr/bin/env bash
# Render apps/Resources/AppIcon.svg → the 10 PNGs required by AppIcon.appiconset.
# Requires: rsvg-convert (brew install librsvg).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apps/Resources/AppIcon.svg"
OUT="$ROOT/apps/Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found. install with: brew install librsvg" >&2
  exit 1
fi

[[ -f "$SRC" ]] || { echo "error: missing SVG source at $SRC" >&2; exit 1; }
mkdir -p "$OUT"

render() {
  local px=$1 name=$2
  rsvg-convert -w "$px" -h "$px" -f png "$SRC" -o "$OUT/$name"
  # sanity-check output dimensions
  local got
  got="$(sips -g pixelWidth "$OUT/$name" | awk '/pixelWidth/ {print $2}')"
  if [[ "$got" != "$px" ]]; then
    echo "error: $name is ${got}px, expected ${px}px" >&2
    exit 1
  fi
  printf "  ✓ %-28s %dx%d\n" "$name" "$px" "$px"
}

echo "rendering AppIcon.appiconset …"
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png
echo "done."
