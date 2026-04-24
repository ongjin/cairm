# Cairn

A fast, native macOS file manager that treats local disks and SSH hosts as peers. Built with SwiftUI and a Rust core for indexing and SFTP.

[![Latest release](https://img.shields.io/github/v/release/ongjin/cairn)](https://github.com/ongjin/cairn/releases)

## Install

Download the latest `.dmg` from [Releases](https://github.com/ongjin/cairn/releases) and drag Cairn to `/Applications`. Cairn auto-updates via Sparkle; no package manager required.

## What you get

- Dual-pane folder navigation with `~` collapsing, breadcrumb navigation, and a Finder-parity sidebar.
- Real SSH tabs backed by the native `~/.ssh/config`: host aliases, ProxyCommand, IdentityFile, all of it.
- Drag-and-drop upload/download with progress tracking.
- Streaming subtree search, local and remote.
- `cairn://` URL scheme, `cairn` CLI, and Finder Services menu.

## Build from source

```sh
git clone https://github.com/ongjin/cairn
cd cairn
make run
```

Requires Xcode 17, Rust 1.80+, and xcodegen (`brew install xcodegen`). The first build takes about 2 minutes for the Rust universal static library.

## Release builds (maintainers)

See [docs/RELEASE.md](docs/RELEASE.md).

## Docs

- [USAGE.md](docs/USAGE.md) - Finder and CLI integration, URL scheme.
- [RELEASE.md](docs/RELEASE.md) - release runbook.
- [CHANGELOG.md](CHANGELOG.md) - user-facing changes.

## Contributing

When you open a PR, add a line under `## [Unreleased]` in `CHANGELOG.md`. Keep entries user-facing, not "refactor internal X".

## License

MIT.
