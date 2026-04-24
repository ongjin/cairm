#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <version, e.g. 1.0.0>" >&2; exit 1; }

: "${DEV_IDENTITY?DEV_IDENTITY must be set to sign the release}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Cleaning derived data"
rm -rf build/DerivedData

echo "Building Release ($VERSION)"
CFBundleShortVersionString="$VERSION" make swift-release

APP="build/DerivedData/Build/Products/Release/Cairn.app"

echo "Notarizing app"
scripts/notarize.sh "$APP"

echo "Building DMG"
scripts/make-dmg.sh "$APP" "build/Cairn-$VERSION.dmg"

echo "Signing DMG"
codesign --sign "$DEV_IDENTITY" --timestamp "build/Cairn-$VERSION.dmg"

echo "Notarizing DMG"
scripts/notarize.sh "build/Cairn-$VERSION.dmg"

echo "Done. Artifact: build/Cairn-$VERSION.dmg"
