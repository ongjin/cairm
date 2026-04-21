//! Session registry + walker threads. Folder mode uses `std::fs::read_dir`
//! (depth 1); Subtree mode (Task 3) will use `ignore::WalkBuilder`.
//! Task 4 exercises cancellation + cap edge cases.

use crate::{SearchMode, SearchOptions, SearchStatus};
use cairn_walker::{FileEntry, FileKind, IconKind};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchHandle(pub u64);

struct Session {
    cancel: Arc<AtomicBool>,
    rx: Mutex<Receiver<Vec<FileEntry>>>,
    status: Arc<Mutex<SearchStatus>>,
    // Walker thread handle is intentionally dropped after spawn; the walker
    // polls `cancel` every iteration so it exits promptly on request.
}

static REGISTRY: Lazy<Mutex<HashMap<u64, Arc<Session>>>> = Lazy::new(|| Mutex::new(HashMap::new()));
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

pub(crate) fn start(root: &Path, opts: SearchOptions) -> SearchHandle {
    let id = NEXT_HANDLE.fetch_add(1, Ordering::SeqCst);
    let handle = SearchHandle(id);

    let cancel = Arc::new(AtomicBool::new(false));
    let status = Arc::new(Mutex::new(SearchStatus::Running));
    let (tx, rx) = sync_channel::<Vec<FileEntry>>(4);

    let cancel_w = cancel.clone();
    let status_w = status.clone();
    let root_buf: PathBuf = root.to_path_buf();
    let opts_w = opts.clone();

    thread::spawn(move || {
        let outcome = match opts_w.mode {
            SearchMode::Folder => run_folder(&root_buf, &opts_w, cancel_w, tx),
            SearchMode::Subtree => run_subtree(&root_buf, &opts_w, cancel_w, tx),
        };
        *status_w.lock().unwrap() = outcome;
    });

    REGISTRY.lock().unwrap().insert(
        id,
        Arc::new(Session {
            cancel,
            rx: Mutex::new(rx),
            status,
        }),
    );
    handle
}

pub(crate) fn next_batch(h: SearchHandle) -> Option<Vec<FileEntry>> {
    let session = {
        let reg = REGISTRY.lock().unwrap();
        reg.get(&h.0).cloned()
    }?;

    // Hold the rx lock briefly; the channel is the natural contention point.
    let rx = session.rx.lock().unwrap();
    match rx.recv_timeout(Duration::from_millis(100)) {
        Ok(batch) => Some(batch),
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
            // Walker still running — return empty batch so caller loops again.
            // Swift side ignores empty batches (keep-alive).
            Some(Vec::new())
        }
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
            // Walker finished; evict so the next call short-circuits.
            drop(rx);
            REGISTRY.lock().unwrap().remove(&h.0);
            None
        }
    }
}

pub(crate) fn status(h: SearchHandle) -> SearchStatus {
    let reg = REGISTRY.lock().unwrap();
    match reg.get(&h.0) {
        Some(s) => s.status.lock().unwrap().clone(),
        None => SearchStatus::Done,
    }
}

pub(crate) fn cancel(h: SearchHandle) {
    let reg = REGISTRY.lock().unwrap();
    if let Some(session) = reg.get(&h.0) {
        session.cancel.store(true, Ordering::SeqCst);
    }
}

// --- Walker implementations ---

fn run_folder(
    root: &Path,
    opts: &SearchOptions,
    cancel: Arc<AtomicBool>,
    tx: SyncSender<Vec<FileEntry>>,
) -> SearchStatus {
    let needle = opts.query.to_lowercase();
    let match_all = needle.is_empty();
    let mut buffer: Vec<FileEntry> = Vec::with_capacity(opts.batch_size);
    let mut matched = 0usize;

    let read_dir = match std::fs::read_dir(root) {
        Ok(rd) => rd,
        Err(e) => return SearchStatus::Failed(e.to_string()),
    };

    for entry_res in read_dir {
        if cancel.load(Ordering::SeqCst) {
            return SearchStatus::Done;
        }
        let Ok(entry) = entry_res else { continue };
        let name = match entry.file_name().into_string() {
            Ok(s) => s,
            Err(_) => continue,
        };
        let is_hidden = name.starts_with('.');
        if is_hidden && !opts.show_hidden {
            continue;
        }
        if !match_all && !name.to_lowercase().contains(&needle) {
            continue;
        }
        let Some(fe) = to_file_entry(&entry, name, is_hidden) else {
            continue;
        };
        buffer.push(fe);
        matched += 1;
        if matched >= opts.result_cap {
            let _ = tx.send(std::mem::take(&mut buffer));
            return SearchStatus::Capped;
        }
        if buffer.len() >= opts.batch_size {
            if tx.send(std::mem::take(&mut buffer)).is_err() {
                return SearchStatus::Done;
            }
            buffer = Vec::with_capacity(opts.batch_size);
        }
    }
    if !buffer.is_empty() {
        let _ = tx.send(buffer);
    }
    SearchStatus::Done
}

fn run_subtree(
    root: &Path,
    opts: &SearchOptions,
    cancel: Arc<AtomicBool>,
    tx: SyncSender<Vec<FileEntry>>,
) -> SearchStatus {
    let needle = opts.query.to_lowercase();
    let match_all = needle.is_empty();
    let mut buffer: Vec<FileEntry> = Vec::with_capacity(opts.batch_size);
    let mut matched = 0usize;

    let walker = ignore::WalkBuilder::new(root)
        .hidden(!opts.show_hidden)
        .require_git(false)
        .git_ignore(!opts.show_hidden)
        .git_global(!opts.show_hidden)
        .git_exclude(!opts.show_hidden)
        .build();

    for result in walker {
        if cancel.load(Ordering::SeqCst) {
            return SearchStatus::Done;
        }
        let entry = match result {
            Ok(e) => e,
            Err(_) => continue, // permission / transient errors: skip silently
        };
        // Skip the root itself.
        if entry.path() == root {
            continue;
        }
        let file_name = entry.file_name().to_string_lossy().to_string();
        if !match_all && !file_name.to_lowercase().contains(&needle) {
            continue;
        }
        let Some(fe) = walk_entry_to_file_entry(&entry, file_name) else {
            continue;
        };
        buffer.push(fe);
        matched += 1;
        if matched >= opts.result_cap {
            let _ = tx.send(std::mem::take(&mut buffer));
            return SearchStatus::Capped;
        }
        if buffer.len() >= opts.batch_size {
            if tx.send(std::mem::take(&mut buffer)).is_err() {
                return SearchStatus::Done;
            }
            buffer = Vec::with_capacity(opts.batch_size);
        }
    }
    if !buffer.is_empty() {
        let _ = tx.send(buffer);
    }
    SearchStatus::Done
}

fn walk_entry_to_file_entry(entry: &ignore::DirEntry, name: String) -> Option<FileEntry> {
    let meta = entry.metadata().ok()?;
    let ft = meta.file_type();
    let is_dir = ft.is_dir();
    let kind = if is_dir {
        FileKind::Directory
    } else if ft.is_symlink() {
        FileKind::Symlink
    } else {
        FileKind::Regular
    };
    let size = if is_dir { 0 } else { meta.len() };
    let modified_unix = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let is_hidden = name.starts_with('.');
    let icon_kind = if is_dir {
        IconKind::Folder
    } else {
        IconKind::GenericFile
    };
    Some(FileEntry {
        path: entry.path().to_path_buf(),
        name,
        size,
        modified_unix,
        kind,
        is_hidden,
        icon_kind,
    })
}

fn to_file_entry(entry: &std::fs::DirEntry, name: String, is_hidden: bool) -> Option<FileEntry> {
    let meta = entry.metadata().ok()?;
    let ft = meta.file_type();
    let is_dir = ft.is_dir();
    let kind = if is_dir {
        FileKind::Directory
    } else if ft.is_symlink() {
        FileKind::Symlink
    } else {
        FileKind::Regular
    };
    let size = if is_dir { 0 } else { meta.len() };
    let modified_unix = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let icon_kind = if is_dir {
        IconKind::Folder
    } else {
        IconKind::GenericFile
    };
    Some(FileEntry {
        path: entry.path(),
        name,
        size,
        modified_unix,
        kind,
        is_hidden,
        icon_kind,
    })
}
