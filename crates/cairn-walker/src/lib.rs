//! cairn-walker — filesystem traversal (single-level listing).
//!
//! In Phase 1 this exposes `list_directory(path, config)` which returns the
//! direct children of `path`. Recursive walking (for Deep Search) lands in
//! Phase 2 and will reuse the same types.

use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct WalkerConfig {
    /// Include entries whose basename starts with `.`.
    pub show_hidden: bool,
    /// Apply `.gitignore` matching when traversing a folder.
    pub respect_gitignore: bool,
    /// Hard-coded exclusion globs applied on top of `.gitignore`.
    /// Only effective when `respect_gitignore == true`.
    pub exclude_patterns: Vec<String>,
}

impl Default for WalkerConfig {
    fn default() -> Self {
        Self {
            show_hidden: false,
            respect_gitignore: true,
            exclude_patterns: vec![
                ".git".into(),
                "node_modules".into(),
                "target".into(),
                ".next".into(),
                "build".into(),
                "dist".into(),
            ],
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEntry {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
    pub modified_unix: i64,
    pub kind: FileKind,
    pub is_hidden: bool,
    pub icon_kind: IconKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    Directory,
    Regular,
    Symlink,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IconKind {
    Folder,
    GenericFile,
    ExtensionHint(String),
}

#[derive(Debug, thiserror::Error)]
pub enum WalkerError {
    #[error("permission denied")]
    PermissionDenied,
    #[error("not found")]
    NotFound,
    #[error("not a directory")]
    NotDirectory,
    #[error("io error: {0}")]
    Io(String),
}

pub fn list_directory(
    _path: &Path,
    _config: &WalkerConfig,
) -> Result<Vec<FileEntry>, WalkerError> {
    // Real implementation arrives in Task 2.
    Ok(Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_has_common_excludes() {
        let cfg = WalkerConfig::default();
        assert!(cfg.exclude_patterns.iter().any(|p| p == "node_modules"));
        assert!(cfg.exclude_patterns.iter().any(|p| p == ".git"));
    }

    #[test]
    fn list_directory_returns_empty_stub() {
        let tmp = std::env::temp_dir();
        let result = list_directory(&tmp, &WalkerConfig::default()).unwrap();
        assert!(result.is_empty());
    }
}
