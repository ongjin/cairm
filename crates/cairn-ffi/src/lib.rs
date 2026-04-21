//! cairn-ffi — the only crate the Swift app sees.
//!
//! Phase 1 API (revised for swift-bridge 0.1.59 upstream limit on
//! `Result<Vec<TransparentStruct>, E>`):
//!   - new_engine() -> Engine
//!   - engine.list_directory(path) -> Result<FileListing, WalkerError>
//!   - engine.set_show_hidden(bool)
//!   - file_listing.len() -> usize
//!   - file_listing.entry(i) -> FileEntry
//!
//! Swift wrapper (see apps/.../CairnEngine.swift) unpacks FileListing into
//! a `[FileEntry]` array so callers see the same shape the plan intended.
//!
//! NOTE: swift-bridge's `#[bridge]` macro expands opaque type declarations
//! into top-level `extern "C"` functions that cast `*mut T` to `*mut T`.
//! Clippy flags that as `unnecessary_cast`, but the redundancy is in the
//! generated code we don't control — hence the crate-level allow below.

#![allow(clippy::unnecessary_cast)]

use std::path::Path;

#[swift_bridge::bridge]
mod ffi {
    // NOTE: enums must be declared before the struct that references them,
    // because swift-bridge emits types into the C header in declaration order
    // and C requires complete types for struct fields (no forward refs).
    enum FileKind {
        Directory,
        Regular,
        Symlink,
    }

    enum IconKind {
        Folder,
        GenericFile,
        ExtensionHint(String),
    }

    #[swift_bridge(swift_repr = "struct")]
    struct FileEntry {
        path: String,
        name: String,
        size: u64,
        modified_unix: i64,
        kind: FileKind,
        is_hidden: bool,
        icon_kind: IconKind,
    }

    enum WalkerError {
        PermissionDenied,
        NotFound,
        NotDirectory,
        Io(String),
    }

    extern "Rust" {
        type Engine;

        fn new_engine() -> Engine;
        fn list_directory(&self, path: String) -> Result<FileListing, WalkerError>;
        fn set_show_hidden(&mut self, show: bool);
    }

    extern "Rust" {
        type FileListing;

        fn len(&self) -> usize;
        fn entry(&self, index: usize) -> FileEntry;
    }
}

// ---- Engine + FileListing (opaque) ------------------------------------------

pub struct Engine {
    inner: cairn_core::Engine,
}

pub struct FileListing {
    entries: Vec<cairn_walker::FileEntry>,
}

fn new_engine() -> Engine {
    Engine {
        inner: cairn_core::Engine::new(),
    }
}

impl Engine {
    fn list_directory(&self, path: String) -> Result<FileListing, ffi::WalkerError> {
        let entries = self
            .inner
            .list_directory(Path::new(&path))
            .map_err(wire_walker_error)?;
        Ok(FileListing { entries })
    }

    fn set_show_hidden(&mut self, show: bool) {
        self.inner.set_show_hidden(show);
    }
}

impl FileListing {
    fn len(&self) -> usize {
        self.entries.len()
    }

    /// Panics if `index >= len()`. Swift wrapper iterates `0..len` so out-of-bounds
    /// would indicate a programming error, not recoverable state.
    fn entry(&self, index: usize) -> ffi::FileEntry {
        wire_file_entry(self.entries[index].clone())
    }
}

// ---- Wire-type conversions --------------------------------------------------

fn wire_file_entry(e: cairn_walker::FileEntry) -> ffi::FileEntry {
    ffi::FileEntry {
        path: e.path.to_string_lossy().into_owned(),
        name: e.name,
        size: e.size,
        modified_unix: e.modified_unix,
        kind: wire_file_kind(e.kind),
        is_hidden: e.is_hidden,
        icon_kind: wire_icon_kind(e.icon_kind),
    }
}

fn wire_file_kind(k: cairn_walker::FileKind) -> ffi::FileKind {
    match k {
        cairn_walker::FileKind::Directory => ffi::FileKind::Directory,
        cairn_walker::FileKind::Regular => ffi::FileKind::Regular,
        cairn_walker::FileKind::Symlink => ffi::FileKind::Symlink,
    }
}

fn wire_icon_kind(k: cairn_walker::IconKind) -> ffi::IconKind {
    match k {
        cairn_walker::IconKind::Folder => ffi::IconKind::Folder,
        cairn_walker::IconKind::GenericFile => ffi::IconKind::GenericFile,
        cairn_walker::IconKind::ExtensionHint(s) => ffi::IconKind::ExtensionHint(s),
    }
}

fn wire_walker_error(e: cairn_walker::WalkerError) -> ffi::WalkerError {
    use cairn_walker::WalkerError as W;
    match e {
        W::PermissionDenied => ffi::WalkerError::PermissionDenied,
        W::NotFound => ffi::WalkerError::NotFound,
        W::NotDirectory => ffi::WalkerError::NotDirectory,
        W::Io(msg) => ffi::WalkerError::Io(msg),
    }
}

// ---- Rust-side smoke test ---------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // ffi::WalkerError doesn't implement Debug (swift-bridge macro limitation),
    // so we can't use `.expect()` or `.unwrap()` on results — we match manually.
    fn list_or_panic(engine: &Engine, path: String) -> FileListing {
        match engine.list_directory(path) {
            Ok(l) => l,
            Err(_) => panic!("list_directory failed on temp dir"),
        }
    }

    #[test]
    fn engine_lists_temp_dir_without_error() {
        let engine = new_engine();
        let path = std::env::temp_dir().to_string_lossy().into_owned();
        let listing = list_or_panic(&engine, path);
        // We don't assert a non-zero count — macOS /tmp can be 0-visible under sandbox
        // or filled; this test only asserts the pipeline doesn't error.
        let _ = listing.len();
    }

    #[test]
    fn file_listing_entry_matches_length() {
        // Smoke test for the indexed-entry access path.
        let engine = new_engine();
        let path = std::env::temp_dir().to_string_lossy().into_owned();
        let listing = list_or_panic(&engine, path);
        let n = listing.len();
        for i in 0..n {
            let _ = listing.entry(i);
        }
    }
}
