//! cairn-walker — filesystem traversal (single-level listing).
//!
//! In Phase 1 this exposes `list_directory(path, config)` which returns the
//! direct children of `path`. Recursive walking (for Deep Search) lands in
//! Phase 2 and will reuse the same types.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

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

pub fn list_directory(path: &Path, config: &WalkerConfig) -> Result<Vec<FileEntry>, WalkerError> {
    // Normalize & validate target.
    let metadata = fs::metadata(path).map_err(io_to_walker_error)?;
    if !metadata.is_dir() {
        return Err(WalkerError::NotDirectory);
    }

    // Build a .gitignore matcher (scoped to this directory).
    let gitignore = if config.respect_gitignore {
        let mut builder = ignore::gitignore::GitignoreBuilder::new(path);
        // Include a .gitignore in this folder if any.
        let gi_file = path.join(".gitignore");
        if gi_file.exists() {
            builder.add(gi_file);
        }
        Some(
            builder
                .build()
                .map_err(|e| WalkerError::Io(e.to_string()))?,
        )
    } else {
        None
    };

    let mut out = Vec::new();

    let rd = fs::read_dir(path).map_err(io_to_walker_error)?;
    for entry in rd {
        let entry = entry.map_err(io_to_walker_error)?;
        let name = match entry.file_name().into_string() {
            Ok(s) => s,
            Err(_) => continue, // skip non-UTF-8 names — Phase 2 can revisit
        };

        // Always exclude .DS_Store regardless of config.
        if name == ".DS_Store" {
            continue;
        }

        let is_hidden = name.starts_with('.');
        if is_hidden && !config.show_hidden {
            continue;
        }

        let entry_path = entry.path();

        // Kind from readdir's `d_type` — no stat syscall, no TCC trigger.
        // macOS TCC gates `stat("/Users/x/Desktop")`, `stat("…/Documents")`,
        // etc. individually, so issuing stat while listing `~` produces a
        // chain of blocking system prompts (one per gated folder).
        // Using `file_type()` derives dir/file/symlink from the dirent buffer
        // the parent read produced, which is already permitted once parent
        // access was allowed. Stat is deferred until we've filtered for
        // TCC-sensitive paths below.
        let file_type = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => {
                out.push(FileEntry {
                    path: entry_path.clone(),
                    name: name.clone(),
                    size: 0,
                    modified_unix: 0,
                    kind: FileKind::Regular,
                    is_hidden,
                    icon_kind: classify_icon(&name, /* is_dir= */ false),
                });
                continue;
            }
        };

        let raw_kind = if file_type.is_dir() {
            FileKind::Directory
        } else if file_type.is_symlink() {
            FileKind::Symlink
        } else {
            FileKind::Regular
        };

        // Fetch size + mtime via stat, but skip the call for TCC-restricted
        // paths (e.g. `~/Desktop`, `~/Documents`) — each of those is a
        // synchronous user prompt under the macOS sandbox and listing `~`
        // would fire one after another. Entries for those paths still appear
        // in the listing with size=0 / mtime=0; when the user actually
        // navigates into the folder, the resulting `read_dir(path)` is a
        // single TCC check at the appropriate moment.
        let skip_stat = is_tcc_restricted_path(&entry_path);
        let metadata = if skip_stat {
            None
        } else {
            fs::metadata(&entry_path).ok()
        };

        let resolved_kind = match (raw_kind, metadata.as_ref()) {
            (FileKind::Symlink, Some(metadata)) if metadata.is_dir() => FileKind::Directory,
            _ => raw_kind,
        };

        // gitignore check (directories need trailing slash semantics for some matchers).
        if let Some(gi) = &gitignore {
            let m = gi.matched(&entry_path, matches!(resolved_kind, FileKind::Directory));
            if m.is_ignore() {
                continue;
            }
        }

        // Hardcoded exclusion patterns (simple name match).
        if config.respect_gitignore && config.exclude_patterns.iter().any(|p| p == &name) {
            continue;
        }

        let size = if matches!(resolved_kind, FileKind::Directory) {
            0
        } else {
            metadata.as_ref().map(|m| m.len()).unwrap_or(0)
        };

        let modified_unix = metadata
            .as_ref()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let icon_kind = classify_icon(&name, matches!(resolved_kind, FileKind::Directory));

        out.push(FileEntry {
            path: entry_path,
            name,
            size,
            modified_unix,
            kind: resolved_kind,
            is_hidden,
            icon_kind,
        });
    }

    // Sort: directories first, then name asc (case-insensitive).
    //
    // Naively calling `a.name.to_lowercase().cmp(&b.name.to_lowercase())`
    // inside the comparator allocates two fresh Strings per comparison —
    // ~N·log2(N)·2 allocations. On a 50k-entry node_modules listing that
    // is >1.5M heap allocs just for sorting. `sort_by_cached_key` evaluates
    // the key function exactly once per element, collapsing this to N
    // allocations. Sort key: `(!is_dir, lower(name))` — `false` (dir) sorts
    // before `true` (file), then ASCII-case-folded name.
    out.sort_by_cached_key(|e| {
        let is_dir = matches!(e.kind, FileKind::Directory);
        (!is_dir, e.name.to_lowercase())
    });

    Ok(out)
}

fn classify_icon(name: &str, is_dir: bool) -> IconKind {
    if is_dir {
        return IconKind::Folder;
    }
    match name.rsplit_once('.') {
        Some((_, ext)) if !ext.is_empty() && !ext.contains(' ') => {
            IconKind::ExtensionHint(ext.to_lowercase())
        }
        _ => IconKind::GenericFile,
    }
}

fn io_to_walker_error(e: std::io::Error) -> WalkerError {
    use std::io::ErrorKind;
    match e.kind() {
        ErrorKind::NotFound => WalkerError::NotFound,
        ErrorKind::PermissionDenied => WalkerError::PermissionDenied,
        _ => WalkerError::Io(e.to_string()),
    }
}

/// Returns true if `path` is a macOS TCC-gated absolute path that would
/// fire a user consent prompt when `stat` is issued from a sandboxed app
/// without the corresponding folder entitlement.
///
/// macOS enforces per-path TCC on Desktop / Documents / Downloads /
/// Movies / Music / Pictures / Public (each has its own TCC domain).
/// Listing `~` iterates these as children and would otherwise produce a
/// cascade of blocking prompts — one per gated folder — before the user
/// ever sees the home view. We skip stat for these to keep listing
/// `~` itself prompt-free; access to their contents still goes through
/// the standard single prompt when the user navigates in.
fn is_tcc_restricted_path(path: &Path) -> bool {
    const GATED: &[&str] = &[
        "Desktop",
        "Documents",
        "Downloads",
        "Movies",
        "Music",
        "Pictures",
        "Public",
    ];
    let home = match std::env::var_os("HOME") {
        Some(h) => PathBuf::from(h),
        None => return false,
    };
    GATED.iter().any(|sub| path == home.join(sub))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::os::unix::fs::symlink;

    #[test]
    fn default_config_has_common_excludes() {
        let cfg = WalkerConfig::default();
        assert!(cfg.exclude_patterns.iter().any(|p| p == "node_modules"));
        assert!(cfg.exclude_patterns.iter().any(|p| p == ".git"));
    }

    #[test]
    fn symlink_to_directory_is_resolved_to_directory_when_stat_is_allowed() {
        let tempdir = tempfile::tempdir().expect("create tempdir");
        let root = tempdir.path();

        fs::create_dir(root.join("real_dir")).expect("create directory");
        fs::write(root.join("real_file"), b"content").expect("create file");
        symlink(root.join("real_dir"), root.join("dir_link")).expect("create dir symlink");
        symlink(root.join("real_file"), root.join("file_link")).expect("create file symlink");

        let entries = list_directory(
            root,
            &WalkerConfig {
                show_hidden: true,
                respect_gitignore: false,
                exclude_patterns: Vec::new(),
            },
        )
        .expect("list directory");
        let kinds: HashMap<_, _> = entries
            .into_iter()
            .map(|entry| (entry.name, entry.kind))
            .collect();

        assert_eq!(kinds.get("real_dir"), Some(&FileKind::Directory));
        assert_eq!(kinds.get("real_file"), Some(&FileKind::Regular));
        assert_eq!(kinds.get("dir_link"), Some(&FileKind::Directory));
        assert_eq!(kinds.get("file_link"), Some(&FileKind::Symlink));
    }
}
