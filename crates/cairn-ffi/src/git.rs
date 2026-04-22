use cairn_git::snapshot;
use std::path::Path;

#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct FfiGitSnapshot {
        branch: String,            // "" 이면 no branch
        modified_count: u32,
        untracked_count: u32,
        added_count: u32,
        deleted_count: u32,
    }

    extern "Rust" {
        fn ffi_git_snapshot(root: String) -> Option<FfiGitSnapshot>;
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
