use cairn_git::{snapshot, GitSnapshot};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct FfiGitSnapshot {
        branch: String, // "" 이면 no branch
        modified_count: u32,
        untracked_count: u32,
        added_count: u32,
        deleted_count: u32,
    }

    extern "Rust" {
        type GitPathList;

        fn len(&self) -> usize;
        fn at(&self, index: usize) -> String;
    }

    extern "Rust" {
        type GitFullSnapshot;

        fn branch(&self) -> String;
        fn modified_count(&self) -> u32;
        fn added_count(&self) -> u32;
        fn deleted_count(&self) -> u32;
        fn untracked_count(&self) -> u32;
        fn modified_len(&self) -> usize;
        fn modified_at(&self, index: usize) -> String;
        fn added_len(&self) -> usize;
        fn added_at(&self, index: usize) -> String;
        fn deleted_len(&self) -> usize;
        fn deleted_at(&self, index: usize) -> String;
        fn untracked_len(&self) -> usize;
        fn untracked_at(&self, index: usize) -> String;
    }

    extern "Rust" {
        fn ffi_git_snapshot(root: String) -> Option<FfiGitSnapshot>;
        fn ffi_git_modified_paths(root: String) -> GitPathList;
        fn ffi_git_added_paths(root: String) -> GitPathList;
        fn ffi_git_deleted_paths(root: String) -> GitPathList;
        fn ffi_git_untracked_paths(root: String) -> GitPathList;
        // Bulk: one libgit2 walk → branch + counts + all four path lists.
        // Replaces the 5-call sequence in Swift's `GitService.refresh()` so a
        // refresh costs one repo scan instead of four (`paths_of` re-runs the
        // walk each time on the legacy fns above).
        fn ffi_git_full_snapshot(root: String) -> Option<GitFullSnapshot>;
    }
}

pub struct GitPathList {
    paths: Vec<String>,
}

impl GitPathList {
    fn len(&self) -> usize {
        self.paths.len()
    }

    fn at(&self, index: usize) -> String {
        self.paths[index].clone()
    }
}

/// Bundle of one libgit2 status walk, exposed to Swift via per-list accessors
/// (swift-bridge's `swift_repr = "struct"` doesn't carry `Vec<String>` fields,
/// hence the opaque-type + `*_at(i)` shape — same idiom as `GitPathList`).
pub struct GitFullSnapshot {
    branch: String,
    modified: Vec<String>,
    added: Vec<String>,
    deleted: Vec<String>,
    untracked: Vec<String>,
}

impl GitFullSnapshot {
    fn branch(&self) -> String {
        self.branch.clone()
    }
    fn modified_count(&self) -> u32 {
        self.modified.len() as u32
    }
    fn added_count(&self) -> u32 {
        self.added.len() as u32
    }
    fn deleted_count(&self) -> u32 {
        self.deleted.len() as u32
    }
    fn untracked_count(&self) -> u32 {
        self.untracked.len() as u32
    }
    fn modified_len(&self) -> usize {
        self.modified.len()
    }
    fn modified_at(&self, index: usize) -> String {
        self.modified[index].clone()
    }
    fn added_len(&self) -> usize {
        self.added.len()
    }
    fn added_at(&self, index: usize) -> String {
        self.added[index].clone()
    }
    fn deleted_len(&self) -> usize {
        self.deleted.len()
    }
    fn deleted_at(&self, index: usize) -> String {
        self.deleted[index].clone()
    }
    fn untracked_len(&self) -> usize {
        self.untracked.len()
    }
    fn untracked_at(&self, index: usize) -> String {
        self.untracked[index].clone()
    }
}

fn collect_paths(set: &HashSet<PathBuf>) -> Vec<String> {
    set.iter()
        .map(|p| p.to_string_lossy().into_owned())
        .collect()
}

pub fn ffi_git_full_snapshot(root: String) -> Option<GitFullSnapshot> {
    let snap = snapshot(Path::new(&root))?;
    Some(GitFullSnapshot {
        branch: snap.branch.unwrap_or_default(),
        modified: collect_paths(&snap.modified),
        added: collect_paths(&snap.added),
        deleted: collect_paths(&snap.deleted),
        untracked: collect_paths(&snap.untracked),
    })
}

pub fn ffi_git_snapshot(root: String) -> Option<ffi::FfiGitSnapshot> {
    let snap = snapshot(Path::new(&root))?;
    Some(ffi::FfiGitSnapshot {
        branch: snap.branch.unwrap_or_default(),
        modified_count: snap.modified.len() as u32,
        untracked_count: snap.untracked.len() as u32,
        added_count: snap.added.len() as u32,
        deleted_count: snap.deleted.len() as u32,
    })
}

fn paths_of<F: Fn(&GitSnapshot) -> &HashSet<PathBuf>>(root: String, f: F) -> GitPathList {
    let snap = match snapshot(Path::new(&root)) {
        Some(s) => s,
        None => return GitPathList { paths: Vec::new() },
    };
    let paths = f(&snap)
        .iter()
        .map(|p| p.to_string_lossy().into_owned())
        .collect();
    GitPathList { paths }
}

pub fn ffi_git_modified_paths(root: String) -> GitPathList {
    paths_of(root, |s| &s.modified)
}

pub fn ffi_git_added_paths(root: String) -> GitPathList {
    paths_of(root, |s| &s.added)
}

pub fn ffi_git_deleted_paths(root: String) -> GitPathList {
    paths_of(root, |s| &s.deleted)
}

pub fn ffi_git_untracked_paths(root: String) -> GitPathList {
    paths_of(root, |s| &s.untracked)
}
