# Cairn

The most beautiful open-source file manager for macOS. Built with SwiftUI + Rust.

> ⚠️ **Status:** Phase 0 — Foundation. Not usable yet. See [design spec](./docs/superpowers/specs/2026-04-21-cairn-design.md).

## Features (v1.0 target)

- **Multi-theme** — Glass (default) · Arc · Raycast
- **⌘K Command Palette** — navigation + actions + search, one input
- **Lightning search** — ripgrep-powered, .gitignore-aware

## Architecture

```
SwiftUI app  ──swift-bridge──►  Rust engine (workspace crates)
```

## Build

Prerequisites: Xcode 15+, Rust 1.75+, [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
# Install xcodegen if needed
brew install xcodegen

# Build Rust engine
./scripts/build-rust.sh

# Generate swift-bridge bindings
./scripts/gen-bindings.sh

# Generate Xcode project
cd apps && xcodegen generate

# Build & run
xcodebuild -scheme Cairn -configuration Debug build
open apps/build/Debug/Cairn.app
```

## License

MIT — see [LICENSE](./LICENSE).
