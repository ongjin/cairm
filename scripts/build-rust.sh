#!/usr/bin/env bash
# Build the Rust static library for Cairn as a universal macOS binary.
# Output: target/universal/release/libcairn_ffi.a

set -euo pipefail

cd "$(dirname "$0")/.."

CRATE="cairn-ffi"
LIB="libcairn_ffi.a"
TARGET_DIR="target"
OUT_DIR="$TARGET_DIR/universal/release"

echo "▸ Ensuring Rust targets are installed..."
rustup target add aarch64-apple-darwin x86_64-apple-darwin

echo "▸ Building $CRATE for aarch64-apple-darwin..."
cargo build --release -p "$CRATE" --target aarch64-apple-darwin

echo "▸ Building $CRATE for x86_64-apple-darwin..."
cargo build --release -p "$CRATE" --target x86_64-apple-darwin

echo "▸ Creating universal binary at $OUT_DIR/$LIB..."
mkdir -p "$OUT_DIR"
lipo -create \
  "$TARGET_DIR/aarch64-apple-darwin/release/$LIB" \
  "$TARGET_DIR/x86_64-apple-darwin/release/$LIB" \
  -output "$OUT_DIR/$LIB"

echo "▸ Verifying architectures..."
lipo -info "$OUT_DIR/$LIB"

echo "✓ Built universal static lib: $OUT_DIR/$LIB"
