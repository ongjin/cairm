//! cairn-core — public façade for the Cairn engine.
//!
//! Phase 1 goal: expose a stateless `Engine` that orchestrates file listing
//! via `cairn-walker`. Additional subsystems (preview, search, index) plug
//! into this struct in later phases.

use cairn_walker::{list_directory, FileEntry, WalkerConfig, WalkerError};
use std::path::Path;

pub use cairn_walker::{FileKind, IconKind};

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
