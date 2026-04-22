use cairn_git::{snapshot, GitSnapshot};
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
        fn ffi_git_snapshot(root: String) -> Option<FfiGitSnapshot>;
        fn ffi_git_modified_paths(root: String) -> GitPathList;
        fn ffi_git_added_paths(root: String) -> GitPathList;
        fn ffi_git_deleted_paths(root: String) -> GitPathList;
        fn ffi_git_untracked_paths(root: String) -> GitPathList;
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

fn paths_of<F: Fn(&GitSnapshot) -> &Vec<PathBuf>>(root: String, f: F) -> GitPathList {
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
