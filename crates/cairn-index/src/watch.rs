use crate::store::{FileKind, FileRow, IndexStore};
use notify_debouncer_mini::{new_debouncer, DebouncedEventKind};
use std::collections::HashSet;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Duration;

pub struct Watcher {
    // All Optioned so we can `take()` them in Drop in the exact order needed.
    // Drop order matters because the symbol channel has TWO senders: the one
    // we hold here (`_symbol_tx`) and a clone owned by the watcher event-loop
    // thread. The worker's `rx.recv()` won't return Err until BOTH are gone.
    _inner: Option<Box<dyn std::any::Any + Send>>,
    _watcher_loop: Option<JoinHandle<()>>,
    _symbol_tx: Option<mpsc::Sender<PathBuf>>,
    _symbol_worker: Option<JoinHandle<()>>,
}

impl Drop for Watcher {
    fn drop(&mut self) {
        // 1. Drop the debouncer — closes its events channel, so the
        //    watcher event loop's `for events in rx` returns.
        self._inner.take();
        // 2. Join the watcher event loop — this drops its clone of
        //    `sym_tx`. Without joining first there's a race where we'd
        //    drop our copy of `sym_tx` and try to join the worker while
        //    the loop thread still holds a sender clone, causing
        //    `worker.rx.recv()` to block forever.
        if let Some(h) = self._watcher_loop.take() {
            let _ = h.join();
        }
        // 3. Drop our own sender so the worker sees the channel close.
        self._symbol_tx.take();
        // 4. Join the symbol worker.
        if let Some(h) = self._symbol_worker.take() {
            let _ = h.join();
        }
    }
}

pub fn watch(root: &Path, store: Arc<IndexStore>) -> notify::Result<Watcher> {
    // Canonicalize root so FSEvents' canonical paths (e.g. /private/var vs /var)
    // still strip_prefix cleanly on macOS.
    let root = std::fs::canonicalize(root).unwrap_or_else(|_| root.to_path_buf());
    let (tx, rx) = mpsc::channel();

    let mut debouncer = new_debouncer(Duration::from_millis(200), tx)?;
    debouncer
        .watcher()
        .watch(&root, notify::RecursiveMode::Recursive)?;

    // Channel from watcher thread -> symbol-extraction worker. The watcher
    // thread sends absolute paths whose content rows have already been
    // upserted; the worker runs tree-sitter and writes symbols to redb.
    // Decoupling these means a single multi-MB save (tens-to-hundreds of ms
    // in tree-sitter) doesn't stall subsequent file-row updates.
    let (sym_tx, sym_rx) = mpsc::channel::<PathBuf>();
    let store_for_symbols = store.clone();
    let root_for_symbols = root.clone();
    let symbol_worker = std::thread::spawn(move || {
        symbol_worker_loop(root_for_symbols, store_for_symbols, sym_rx);
    });

    let root_thr = root.clone();
    let sym_tx_thr = sym_tx.clone();
    let watcher_loop = std::thread::spawn(move || {
        for events in rx {
            let events = match events {
                Ok(e) => e,
                Err(_) => continue,
            };
            for ev in events {
                apply_event(&root_thr, &store, &ev.path, ev.kind, &sym_tx_thr);
            }
        }
        // sym_tx_thr dropped here when this thread exits, releasing the
        // watcher loop's hold on the symbol channel.
    });

    Ok(Watcher {
        _inner: Some(Box::new(debouncer)),
        _watcher_loop: Some(watcher_loop),
        _symbol_tx: Some(sym_tx),
        _symbol_worker: Some(symbol_worker),
    })
}

/// Long-running worker that owns tree-sitter symbol extraction. Drains the
/// channel of duplicates between blocking recvs so a burst of saves to the
/// same file (formatter / IDE save-then-touch) only re-extracts once.
fn symbol_worker_loop(root: PathBuf, store: Arc<IndexStore>, rx: mpsc::Receiver<PathBuf>) {
    while let Ok(first) = rx.recv() {
        let mut pending: HashSet<PathBuf> = HashSet::new();
        pending.insert(first);
        // Opportunistically drain anything else already queued. This collapses
        // bursty events (save-on-format, multiple FS events for one logical
        // save) into a single extraction per path.
        while let Ok(p) = rx.try_recv() {
            pending.insert(p);
        }
        for path in pending {
            let rel = match path.strip_prefix(&root) {
                Ok(r) => r.to_string_lossy().into_owned(),
                Err(_) => continue,
            };
            if rel.is_empty() {
                continue;
            }
            // Re-check existence: a delete event may have raced past us
            // between the watcher upsert and the worker dequeue.
            if !path.exists() {
                continue;
            }
            let syms = crate::symbols::extract_from_file(&path);
            if !syms.is_empty() {
                let _ = store.put_symbols(&rel, &syms);
            }
        }
    }
}

fn apply_event(
    root: &Path,
    store: &IndexStore,
    path: &Path,
    kind: DebouncedEventKind,
    sym_tx: &mpsc::Sender<PathBuf>,
) {
    let rel = match path.strip_prefix(root) {
        Ok(r) => r.to_string_lossy().into_owned(),
        Err(_) => return,
    };
    if rel.is_empty() || rel.starts_with(".git") {
        return;
    }

    if kind == DebouncedEventKind::Any {
        if !path.exists() {
            let _ = store.delete_file(&rel);
            return;
        }
        let md = match path.metadata() {
            Ok(m) => m,
            Err(_) => return,
        };
        let ft = md.file_type();
        let kind_enum = if ft.is_dir() {
            FileKind::Directory
        } else if ft.is_symlink() {
            FileKind::Symlink
        } else {
            FileKind::Regular
        };
        let row = FileRow {
            size: md.len(),
            mtime_unix: md.mtime(),
            kind: kind_enum,
            git_status: None,
            symbol_count: 0,
        };
        let _ = store.put_file(&rel, &row);
        if matches!(kind_enum, FileKind::Regular) {
            // Hand off to the symbol-extraction worker. Channel send is ~µs;
            // tree-sitter parse can be tens of ms — keeping it off this
            // thread is the whole point of this refactor.
            let _ = sym_tx.send(path.to_path_buf());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::IndexStore;
    use std::fs;
    use std::sync::Arc;
    use tempfile::TempDir;

    #[test]
    fn new_file_gets_indexed() {
        let tmp = TempDir::new().unwrap();
        let db_tmp = TempDir::new().unwrap();
        let store = Arc::new(IndexStore::open(&db_tmp.path().join("i.redb")).unwrap());
        let _w = watch(tmp.path(), store.clone()).unwrap();

        std::thread::sleep(Duration::from_millis(200));
        fs::write(tmp.path().join("added.txt"), "x").unwrap();
        std::thread::sleep(Duration::from_millis(1500));

        let got = store.get_file("added.txt").unwrap();
        assert!(
            got.is_some(),
            "FSEvents-driven index update should have added 'added.txt'"
        );
    }

    #[test]
    fn symbols_extracted_off_watcher_thread() {
        // Saving a .rs file should yield symbols via the background worker.
        let tmp = TempDir::new().unwrap();
        let db_tmp = TempDir::new().unwrap();
        let store = Arc::new(IndexStore::open(&db_tmp.path().join("i.redb")).unwrap());
        let _w = watch(tmp.path(), store.clone()).unwrap();

        std::thread::sleep(Duration::from_millis(200));
        fs::write(tmp.path().join("hello.rs"), "struct Foo; fn bar() {}").unwrap();
        std::thread::sleep(Duration::from_millis(1500));

        let syms = store.query_symbols("bar", 16).unwrap();
        assert!(
            syms.iter()
                .any(|(rel, s)| rel == "hello.rs" && s.name == "bar"),
            "symbol worker should have extracted `bar` from hello.rs"
        );
    }
}
