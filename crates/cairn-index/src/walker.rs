use crate::store::{FileKind, FileRow, IndexStore};
use ignore::{DirEntry as IgnoreDirEntry, WalkBuilder, WalkState};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::sync::Arc;

/// macOS `chflags` user-hidden flag. `~/Library` is the canonical example —
/// not dot-prefixed so a name check misses it, but Finder hides it. Without
/// this skip, walking Home spends >90% of its time enumerating Library.
const UF_HIDDEN: u32 = 0x8000;

#[cfg(target_os = "macos")]
fn is_chflags_hidden(entry: &IgnoreDirEntry) -> bool {
    use std::os::darwin::fs::MetadataExt as DarwinMetadataExt;
    entry
        .metadata()
        .map(|m| m.st_flags() & UF_HIDDEN != 0)
        .unwrap_or(false)
}

#[cfg(not(target_os = "macos"))]
fn is_chflags_hidden(_entry: &IgnoreDirEntry) -> bool {
    false
}

fn is_dotted(name: &str) -> bool {
    name.starts_with('.') && name != "." && name != ".."
}

/// macOS bundle/package directories: opaque to the user (Finder shows them as
/// a single icon) and walking into them is both pointless and risky — e.g.
/// `Music Library.musiclibrary` triggers a TCC prompt for Apple Music access.
/// Match by suffix so e.g. `Foo.app` and `MyLib.framework` are caught
/// regardless of name.
const PACKAGE_EXTENSIONS: &[&str] = &[
    ".app",
    ".bundle",
    ".framework",
    ".xcframework",
    ".lproj",
    ".nib",
    ".car",
    ".xcassets",
    ".pkg",
    ".mpkg",
    ".musiclibrary",   // Apple Music — TCC trigger
    ".photoslibrary",  // Photos — TCC trigger
    ".tvlibrary",      // Apple TV
    ".dmg",
];

fn is_macos_package(name: &str) -> bool {
    let lower = name.to_lowercase();
    PACKAGE_EXTENSIONS.iter().any(|ext| lower.ends_with(ext))
}

/// Directory names that should never be descended into. These are uniformly
/// noisy for a file-finder UX (build artefacts, language-specific caches,
/// vendored deps) and account for the bulk of indexing time when the user
/// opens a home / projects parent directory. The skip is by directory NAME,
/// not path, so `node_modules` anywhere in the tree is pruned.
///
/// Hidden dotfile directories are NOT enumerated here — `.skipsHiddenFiles`
/// in the Swift fallback handles those, and the user can still navigate INTO
/// them explicitly to index. The set below is for visible-but-noisy dirs
/// the user almost never wants to fuzzy-search through.
const SKIP_DIR_NAMES: &[&str] = &[
    ".git",
    // ~/Library is normally chflags-hidden (caught by is_chflags_hidden), but
    // some users have unset that flag (showing Library as a normal folder in
    // Finder). Without this name skip the walker descends into Application
    // Support / Containers / Group Containers and trips the macOS Sequoia
    // "access another app's data" TCC prompt over and over. The user can
    // still navigate INTO ~/Library explicitly — that opens it as a walk
    // root (depth=0 always passes), so contents at depth=1+ get indexed.
    "Library",
    "node_modules",
    "target",        // Rust
    "build",         // generic + Xcode
    "Build",         // Xcode
    "DerivedData",   // Xcode
    "Pods",          // CocoaPods
    ".next",         // Next.js
    ".nuxt",         // Nuxt
    ".svelte-kit",   // SvelteKit
    "dist",          // generic JS bundlers
    ".cache",        // generic
    ".gradle",       // Gradle
    ".venv",         // Python
    "venv",          // Python
    "__pycache__",   // Python
    "vendor",        // PHP / Go / Ruby
    ".terraform",    // Terraform
];

fn should_skip_dir(name: &str) -> bool {
    SKIP_DIR_NAMES.iter().any(|s| *s == name)
}

/// Cap at 8 — empirically diminishing returns past that for FS-bound work
/// on macOS APFS, and beyond 8 the contention on the channel + the cost of
/// extra thread setup outweighs the parallelism win.
const MAX_WALKER_THREADS: usize = 8;

fn walker_thread_count() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        .min(MAX_WALKER_THREADS)
        .max(1)
}

/// Per-entry payload sent from worker threads to the main collector. Carries
/// the fully-built `FileRow` plus an optional absolute path for the symbol-
/// extraction phase (only set for regular files small enough to be worth
/// parsing).
struct WalkItem {
    rel: String,
    row: FileRow,
    source: Option<PathBuf>,
}

/// Walk the tree at `root`, write file rows in a single bulk transaction,
/// and return the list of source-file paths that the caller should hand to a
/// background thread for symbol extraction. Splitting these phases keeps the
/// file index queryable as soon as the walk's single fsync commits.
///
/// Internally this fans out the directory traversal across a small worker
/// pool via `ignore::WalkBuilder::build_parallel()`. Each worker assembles
/// per-entry `FileRow` values (stat + git-status lookups happen in parallel)
/// and ships them over a channel to a single collector. redb's
/// single-writer model means we still serialize the actual DB write — but
/// stat'ing 100k files is the expensive part on big monorepos, and that
/// part now scales with cores.
pub fn walk_into(
    root: &Path,
    store: &IndexStore,
) -> Result<(usize, Vec<(String, std::path::PathBuf)>), crate::IndexError> {
    let git_snap = Arc::new(cairn_git::snapshot(root));
    let root_buf = root.to_path_buf();

    let (tx, rx) = mpsc::channel::<WalkItem>();

    let walker = WalkBuilder::new(root)
        // We do our own filtering. Disable gitignore / hidden / parents so
        // behaviour matches the prior `walkdir`-based walker exactly: the
        // index sees every file (gitignored or not) so the user can still
        // fuzzy-find e.g. `target/Cargo.lock`. Search-time gitignore is the
        // job of cairn-search.
        .standard_filters(false)
        .hidden(false)
        .parents(false)
        .git_ignore(false)
        .git_global(false)
        .git_exclude(false)
        .require_git(false)
        .follow_links(false)
        .threads(walker_thread_count())
        .filter_entry(move |e| {
            // Always descend into the explicit root — otherwise asking the
            // index to walk e.g. ~/Library directly would yield zero entries.
            if e.depth() == 0 {
                return true;
            }
            let name = e.file_name().to_string_lossy();
            if should_skip_dir(&name) {
                return false;
            }
            // Hidden conventions (Finder default): dot-prefixed and the
            // macOS-specific chflags UF_HIDDEN bit. Files under a hidden dir
            // are pruned implicitly because we never descend into it.
            let is_dir = e.file_type().map(|t| t.is_dir()).unwrap_or(false);
            if is_dir && (is_dotted(&name) || is_macos_package(&name) || is_chflags_hidden(e)) {
                return false;
            }
            true
        })
        .build_parallel();

    walker.run(|| {
        let tx = tx.clone();
        let git_snap = Arc::clone(&git_snap);
        let root_buf = root_buf.clone();
        Box::new(move |entry| {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => return WalkState::Continue,
            };
            // Skip the root itself (depth 0). filter_entry above lets it
            // through so descent happens, but we don't want a row for it.
            if entry.depth() == 0 {
                return WalkState::Continue;
            }
            let path = entry.path();
            let rel = match path.strip_prefix(&root_buf) {
                Ok(r) => r.to_string_lossy().into_owned(),
                Err(_) => return WalkState::Continue,
            };
            let ft = match entry.file_type() {
                Some(f) => f,
                None => return WalkState::Continue,
            };
            let kind = if ft.is_dir() {
                FileKind::Directory
            } else if ft.is_symlink() {
                FileKind::Symlink
            } else {
                FileKind::Regular
            };
            let md = match entry.metadata() {
                Ok(m) => m,
                Err(_) => return WalkState::Continue,
            };
            let git_status = match git_snap.as_ref() {
                Some(snap) => {
                    let pb = std::path::PathBuf::from(&rel);
                    if snap.modified.contains(&pb) {
                        Some(b'M')
                    } else if snap.added.contains(&pb) {
                        Some(b'A')
                    } else if snap.deleted.contains(&pb) {
                        Some(b'D')
                    } else if snap.untracked.contains(&pb) {
                        Some(b'U')
                    } else {
                        None
                    }
                }
                None => None,
            };
            let row = FileRow {
                size: md.len(),
                mtime_unix: md.mtime(),
                kind,
                git_status,
                symbol_count: 0,
            };
            let source = if matches!(kind, FileKind::Regular) && md.len() <= 256_000 {
                // Only consider files small enough that tree-sitter parsing
                // won't dominate. Minified bundles / sourcemaps are skipped.
                Some(path.to_path_buf())
            } else {
                None
            };
            // If the receiver is gone the walk is being torn down; stop.
            if tx.send(WalkItem { rel, row, source }).is_err() {
                return WalkState::Quit;
            }
            WalkState::Continue
        })
    });
    // Drop the original sender so the receiver loop terminates after all
    // worker clones have also been dropped (workers drop theirs at the end
    // of `walker.run`).
    drop(tx);

    let mut files: Vec<(String, FileRow)> = Vec::new();
    let mut source_files: Vec<(String, std::path::PathBuf)> = Vec::new();
    for item in rx {
        if let Some(abs) = item.source {
            source_files.push((item.rel.clone(), abs));
        }
        files.push((item.rel, item.row));
    }

    let count = files.len();
    store.bulk_put_files(&files)?;
    Ok((count, source_files))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn walk_populates_store_with_regular_files() {
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("a.txt"), "aaa").unwrap();
        fs::write(tmp.path().join("b.swift"), "bb").unwrap();
        fs::create_dir(tmp.path().join("sub")).unwrap();
        fs::write(tmp.path().join("sub/c.md"), "c").unwrap();

        let db_tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&db_tmp.path().join("i.redb")).unwrap();
        let (count, _src) = walk_into(tmp.path(), &store).unwrap();
        assert_eq!(count, 4); // 2 files + 1 dir + 1 file

        let all = store.list_all().unwrap();
        assert!(all.iter().any(|(p, _)| p == "a.txt"));
        assert!(all
            .iter()
            .any(|(p, r)| p == "sub" && matches!(r.kind, FileKind::Directory)));
        assert!(all.iter().any(|(p, _)| p == "sub/c.md"));
    }

    #[test]
    fn walk_skips_dotgit() {
        let tmp = TempDir::new().unwrap();
        fs::create_dir(tmp.path().join(".git")).unwrap();
        fs::write(tmp.path().join(".git/HEAD"), "ref").unwrap();
        fs::write(tmp.path().join("x.txt"), "x").unwrap();

        let db_tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&db_tmp.path().join("i.redb")).unwrap();
        let _ = walk_into(tmp.path(), &store).unwrap();

        let all = store.list_all().unwrap();
        assert!(all.iter().all(|(p, _)| !p.starts_with(".git")));
        assert!(all.iter().any(|(p, _)| p == "x.txt"));
    }
}
