//! Streaming filename search backing the `⌘F` bar in Cairn.
//!
//! Spawns a walker in a background thread and delivers matching entries in
//! batches via a `u64` handle. Callers pull batches with `next_batch` until
//! it returns `None`, then the session is self-cleaned.

mod session;

use cairn_walker::FileEntry;
use std::path::Path;

pub use session::SearchHandle;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SearchMode {
    Folder,
    Subtree,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SearchStatus {
    Running,
    Capped,
    Done,
    Failed(String),
}

#[derive(Clone, Debug)]
pub struct SearchOptions {
    pub query: String,
    pub mode: SearchMode,
    pub show_hidden: bool,
    pub result_cap: usize,
    pub batch_size: usize,
}

impl Default for SearchOptions {
    fn default() -> Self {
        Self {
            query: String::new(),
            mode: SearchMode::Folder,
            show_hidden: false,
            result_cap: 5_000,
            batch_size: 256,
        }
    }
}

/// Begin a search session. Returns a handle the caller will poll via
/// `next_batch` and optionally `cancel`.
pub fn start(root: &Path, opts: SearchOptions) -> SearchHandle {
    session::start(root, opts)
}

/// Pull the next batch of matching entries. Blocks up to ~100ms.
/// Returns `None` once the walker is exhausted (done / capped / cancelled).
pub fn next_batch(h: SearchHandle) -> Option<Vec<FileEntry>> {
    session::next_batch(h)
}

/// Query the latest status of a session. Safe on stale handles.
pub fn status(h: SearchHandle) -> SearchStatus {
    session::status(h)
}

/// Request cancellation. Idempotent and safe on stale handles.
pub fn cancel(h: SearchHandle) {
    session::cancel(h)
}
