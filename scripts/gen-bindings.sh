#!/usr/bin/env bash
# Generate swift-bridge Swift/C bindings by invoking cargo build on cairn-ffi,
# then mirror the generated sources into apps/Sources/Generated/ for Xcode.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "▸ Running cargo build to regenerate bindings..."
cargo build -p cairn-ffi

SRC="crates/cairn-ffi/generated/cairn_ffi"
DST="apps/Sources/Generated"

if [[ ! -d "$SRC" ]]; then
  echo "✗ Bindings not found at $SRC — did cargo build succeed?"
  exit 1
fi

mkdir -p "$DST"
cp "$SRC/cairn_ffi.swift" "$DST/cairn_ffi.swift"
cp "$SRC/cairn_ffi.h" "$DST/cairn_ffi.h"

# swift-bridge runtime Swift sources (공용 헬퍼)
SWIFT_BRIDGE_SRC="$(find target -name 'SwiftBridgeCore.swift' -path '*/swift-bridge-*/*' | head -1)"
if [[ -n "$SWIFT_BRIDGE_SRC" ]]; then
  cp "$SWIFT_BRIDGE_SRC" "$DST/SwiftBridgeCore.swift"
  SWIFT_BRIDGE_H="$(dirname "$SWIFT_BRIDGE_SRC")/SwiftBridgeCore.h"
  cp "$SWIFT_BRIDGE_H" "$DST/SwiftBridgeCore.h"
fi

echo "✓ Bindings copied to $DST/"
ls -1 "$DST"
