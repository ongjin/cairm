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

pub mod git;
pub mod index;

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

    enum PreviewError {
        Binary,
        NotFound,
        PermissionDenied,
        Io(String),
    }

    extern "Rust" {
        type Engine;

        fn new_engine() -> Engine;
        fn list_directory(&self, path: String) -> Result<FileListing, WalkerError>;
        fn set_show_hidden(&mut self, show: bool);
        fn preview_text(&self, path: String) -> Result<String, PreviewError>;
    }

    extern "Rust" {
        type FileListing;

        fn len(&self) -> usize;
        fn entry(&self, index: usize) -> FileEntry;
    }

    extern "Rust" {
        type SearchBatch;

        #[swift_bridge(swift_name = "isEnd")]
        fn is_end(&self) -> bool;
        fn len(&self) -> usize;
        fn entry(&self, index: usize) -> FileEntry;
    }

    extern "Rust" {
        #[swift_bridge(swift_name = "searchStart")]
        fn search_start(root_path: String, query: String, subtree: bool, show_hidden: bool) -> u64;

        #[swift_bridge(swift_name = "searchNextBatch")]
        fn search_next_batch(handle: u64) -> SearchBatch;

        #[swift_bridge(swift_name = "searchCancel")]
        fn search_cancel(handle: u64);
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

    fn preview_text(&self, path: String) -> Result<String, ffi::PreviewError> {
        self.inner
            .preview_text(Path::new(&path))
            .map_err(wire_preview_error)
    }

    fn set_show_hidden(&mut self, show: bool) {
        self.inner.set_show_hidden(show);
    }
}

impl FileListing {
    fn len(&self) -> usize {
        self.entries.len()
    }

    /// Returns an empty entry if `index >= len()`. Swift normally iterates
    /// `0..len`, but a stale index from a refresh race must NOT panic the
    /// process — empty wire struct is the safe degenerate.
    fn entry(&self, index: usize) -> ffi::FileEntry {
        if index >= self.entries.len() {
            return empty_file_entry();
        }
        wire_file_entry(&self.entries[index])
    }
}

// ---- SearchBatch (opaque) ---------------------------------------------------

/// A single batch returned by `search_next_batch`. When `end` is true, the
/// session is exhausted (done / capped / cancelled) and the caller should
/// stop polling. An `end: false` batch with `entries.is_empty()` means
/// "keep-alive" — walker still running, no new matches in the last ~100ms.
pub struct SearchBatch {
    entries: Vec<cairn_walker::FileEntry>,
    end: bool,
}

impl SearchBatch {
    fn is_end(&self) -> bool {
        self.end
    }

    fn len(&self) -> usize {
        self.entries.len()
    }

    /// Returns an empty entry if `index >= len()`. Search batches can race
    /// with cancellation/refresh on the Swift side; an out-of-bounds call
    /// must degrade to empty rather than abort the process.
    fn entry(&self, index: usize) -> ffi::FileEntry {
        if index >= self.entries.len() {
            return empty_file_entry();
        }
        wire_file_entry(&self.entries[index])
    }
}

fn search_start(root_path: String, query: String, subtree: bool, show_hidden: bool) -> u64 {
    use cairn_search::{start, SearchMode, SearchOptions};
    let opts = SearchOptions {
        query,
        mode: if subtree {
            SearchMode::Subtree
        } else {
            SearchMode::Folder
        },
        show_hidden,
        ..Default::default()
    };
    let handle = start(Path::new(&root_path), opts);
    handle.0
}

fn search_next_batch(handle: u64) -> SearchBatch {
    use cairn_search::{next_batch, SearchHandle};
    match next_batch(SearchHandle(handle)) {
        Some(entries) => SearchBatch {
            entries,
            end: false,
        },
        None => SearchBatch {
            entries: Vec::new(),
            end: true,
        },
    }
}

fn search_cancel(handle: u64) {
    use cairn_search::{cancel, SearchHandle};
    cancel(SearchHandle(handle));
}

// ---- Wire-type conversions --------------------------------------------------

/// Safe zero-value `FileEntry` for out-of-bounds accessor calls. swift-bridge
/// generated structs don't implement `Default`, so we hand-construct the
/// emptiest plausible row (Regular file, generic icon, all-zero metadata).
fn empty_file_entry() -> ffi::FileEntry {
    ffi::FileEntry {
        path: String::new(),
        name: String::new(),
        size: 0,
        modified_unix: 0,
        kind: ffi::FileKind::Regular,
        is_hidden: false,
        icon_kind: ffi::IconKind::GenericFile,
    }
}

fn wire_file_entry(e: &cairn_walker::FileEntry) -> ffi::FileEntry {
    ffi::FileEntry {
        path: e.path.to_string_lossy().into_owned(),
        name: e.name.clone(),
        size: e.size,
        modified_unix: e.modified_unix,
        kind: wire_file_kind(e.kind),
        is_hidden: e.is_hidden,
        icon_kind: wire_icon_kind(&e.icon_kind),
    }
}

fn wire_file_kind(k: cairn_walker::FileKind) -> ffi::FileKind {
    match k {
        cairn_walker::FileKind::Directory => ffi::FileKind::Directory,
        cairn_walker::FileKind::Regular => ffi::FileKind::Regular,
        cairn_walker::FileKind::Symlink => ffi::FileKind::Symlink,
    }
}

fn wire_icon_kind(k: &cairn_walker::IconKind) -> ffi::IconKind {
    match k {
        cairn_walker::IconKind::Folder => ffi::IconKind::Folder,
        cairn_walker::IconKind::GenericFile => ffi::IconKind::GenericFile,
        cairn_walker::IconKind::ExtensionHint(s) => ffi::IconKind::ExtensionHint(s.clone()),
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

fn wire_preview_error(e: cairn_core::PreviewError) -> ffi::PreviewError {
    use cairn_core::PreviewError as P;
    match e {
        P::Binary => ffi::PreviewError::Binary,
        P::NotFound => ffi::PreviewError::NotFound,
        P::PermissionDenied => ffi::PreviewError::PermissionDenied,
        P::Io(msg) => ffi::PreviewError::Io(msg),
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

    #[test]
    fn engine_preview_text_on_cargo_toml_roundtrips() {
        let engine = new_engine();
        // This crate's own Cargo.toml is always present and small.
        let path = env!("CARGO_MANIFEST_DIR").to_string() + "/Cargo.toml";
        match engine.preview_text(path) {
            Ok(s) => assert!(s.contains("cairn-ffi")),
            Err(_) => panic!("preview_text failed on Cargo.toml"),
        }
    }
}
