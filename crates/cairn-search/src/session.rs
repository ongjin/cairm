//! Session registry and walker thread. Task 2 fills in the Folder-mode
//! implementation; Task 3 adds Subtree-mode; Task 4 adds cancellation + cap.

use crate::{SearchOptions, SearchStatus};
use cairn_walker::FileEntry;
use std::path::Path;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchHandle(pub u64);

pub(crate) fn start(_root: &Path, _opts: SearchOptions) -> SearchHandle {
    SearchHandle(0)
}

pub(crate) fn next_batch(_h: SearchHandle) -> Option<Vec<FileEntry>> {
    None
}

pub(crate) fn status(_h: SearchHandle) -> SearchStatus {
    SearchStatus::Done
}

pub(crate) fn cancel(_h: SearchHandle) {}
