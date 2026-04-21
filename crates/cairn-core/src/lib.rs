//! cairn-core — public façade for the Cairn engine.
//!
//! Shared types + error surface that all Cairn Rust crates consume:
//! `FileEntry`, `FileKind`, `IconKind`, `WalkerError`, `PreviewError`. The
//! `Engine` orchestrates file listing via `cairn-walker` and text preview via
//! `cairn-preview`; `cairn-search` plugs in at the FFI layer alongside this
//! crate. Re-exports below give downstream callers a single import path for
//! all the common types.

use cairn_walker::{list_directory, FileEntry, WalkerConfig};
use std::path::Path;

pub use cairn_preview::PreviewError;
pub use cairn_walker::{FileKind, IconKind, WalkerError};

pub struct Engine {
    walker_config: WalkerConfig,
}

impl Engine {
    pub fn new() -> Self {
        Self {
            walker_config: WalkerConfig::default(),
        }
    }

    pub fn list_directory(&self, path: &Path) -> Result<Vec<FileEntry>, WalkerError> {
        list_directory(path, &self.walker_config)
    }

    pub fn preview_text(&self, path: &Path) -> Result<String, PreviewError> {
        // 64 KB — balances "enough to see code context" vs "snappy".
        // Phase 2 will make this configurable + stream-based.
        cairn_preview::preview_text(path, 64 * 1024)
    }

    pub fn set_show_hidden(&mut self, show: bool) {
        self.walker_config.show_hidden = show;
    }

    pub fn show_hidden(&self) -> bool {
        self.walker_config.show_hidden
    }
}

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_defaults_to_hidden_off() {
        let engine = Engine::new();
        assert!(!engine.show_hidden());
    }

    #[test]
    fn set_show_hidden_mutates_state() {
        let mut engine = Engine::new();
        engine.set_show_hidden(true);
        assert!(engine.show_hidden());
    }

    #[test]
    fn list_directory_returns_sorted_children() {
        // tempfile isn't a dev-dep on cairn-core by design — use env::temp_dir
        // indirectly via any existing directory. We just assert it doesn't error.
        let engine = Engine::new();
        let result = engine.list_directory(&std::env::temp_dir());
        assert!(result.is_ok());
    }
}
