use crate::store::{FileKind, FileRow, IndexStore};
use notify_debouncer_mini::{new_debouncer, DebouncedEventKind};
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::sync::mpsc;
use std::sync::Arc;
use std::time::Duration;

pub struct Watcher {
    _inner: Box<dyn std::any::Any + Send>,
}

pub fn watch(root: &Path, store: Arc<IndexStore>) -> notify::Result<Watcher> {
    // Canonicalize root so FSEvents' canonical paths (e.g. /private/var vs /var)
    // still strip_prefix cleanly on macOS.
    let root = std::fs::canonicalize(root).unwrap_or_else(|_| root.to_path_buf());
    let (tx, rx) = mpsc::channel();

    let mut debouncer = new_debouncer(Duration::from_millis(200), tx)?;
    debouncer.watcher().watch(&root, notify::RecursiveMode::Recursive)?;

    let root_thr = root.clone();
    std::thread::spawn(move || {
        for events in rx {
            let events = match events { Ok(e) => e, Err(_) => continue };
            for ev in events {
                apply_event(&root_thr, &store, &ev.path, ev.kind);
            }
        }
    });

    Ok(Watcher { _inner: Box::new(debouncer) })
}

fn apply_event(root: &Path, store: &IndexStore, path: &Path, kind: DebouncedEventKind) {
    let rel = match path.strip_prefix(root) {
        Ok(r) => r.to_string_lossy().into_owned(),
        Err(_) => return,
    };
    if rel.is_empty() || rel.starts_with(".git") { return; }

    match kind {
        DebouncedEventKind::Any => {
            if !path.exists() {
                let _ = store.delete_file(&rel);
                return;
            }
            let md = match path.metadata() { Ok(m) => m, Err(_) => return };
            let ft = md.file_type();
            let kind_enum = if ft.is_dir() { FileKind::Directory }
                            else if ft.is_symlink() { FileKind::Symlink }
                            else { FileKind::Regular };
            let row = FileRow {
                size: md.len(),
                mtime_unix: md.mtime(),
                kind: kind_enum,
                git_status: None,
                symbol_count: 0,
            };
            let _ = store.put_file(&rel, &row);
            if matches!(kind_enum, FileKind::Regular) {
                let syms = crate::symbols::extract_from_file(path);
                if !syms.is_empty() { let _ = store.put_symbols(&rel, &syms); }
            }
        }
        _ => {}
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
        assert!(got.is_some(), "FSEvents-driven index update should have added 'added.txt'");
    }
}
