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

# swift-bridge runtime Swift/C sources (RustString 등 공용 헬퍼)
# swift-bridge-build가 out_dir 바로 아래에 생성한다 (bridge별 파일은 out_dir/<name>/).
CORE_DIR="$SRC/.."  # = crates/cairn-ffi/generated
if [[ -f "$CORE_DIR/SwiftBridgeCore.swift" ]]; then
  cp "$CORE_DIR/SwiftBridgeCore.swift" "$DST/SwiftBridgeCore.swift"
  cp "$CORE_DIR/SwiftBridgeCore.h" "$DST/SwiftBridgeCore.h"
else
  echo "✗ SwiftBridgeCore not found at $CORE_DIR — swift-bridge-build API may have changed."
  exit 1
fi

echo "✓ Bindings copied to $DST/"
ls -1 "$DST"
