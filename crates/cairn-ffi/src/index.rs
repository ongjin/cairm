use cairn_index::{
    cache_path_for, query_fuzzy, walk_into, watch, ContentSearch, IndexStore, Watcher,
};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Condvar, Mutex, OnceLock, Weak};

struct SharedIndex {
    store: Arc<IndexStore>,
    _watcher: Mutex<Option<Watcher>>,
    root: PathBuf,
    ready: (Mutex<bool>, Condvar),
}

impl SharedIndex {
    fn new(store: Arc<IndexStore>, root: PathBuf) -> Self {
        Self {
            store,
            _watcher: Mutex::new(None),
            root,
            ready: (Mutex::new(false), Condvar::new()),
        }
    }

    fn wait_until_ready(&self) {
        let (lock, cv) = &self.ready;
        let mut ready = lock.lock().unwrap();
        while !*ready {
            ready = cv.wait(ready).unwrap();
        }
    }

    fn mark_ready(&self) {
        let (lock, cv) = &self.ready;
        *lock.lock().unwrap() = true;
        cv.notify_all();
    }

    fn set_watcher(&self, watcher: Option<Watcher>) {
        *self._watcher.lock().unwrap() = watcher;
    }
}

struct Registry {
    handles: HashMap<u64, Arc<SharedIndex>>,
    roots: HashMap<PathBuf, Weak<SharedIndex>>,
}

static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<u64>> = OnceLock::new();

fn registry() -> &'static Mutex<Registry> {
    REGISTRY.get_or_init(|| {
        Mutex::new(Registry {
            handles: HashMap::new(),
            roots: HashMap::new(),
        })
    })
}
fn next_id() -> u64 {
    let m = NEXT_ID.get_or_init(|| Mutex::new(1));
    let mut g = m.lock().unwrap();
    let id = *g;
    *g += 1;
    id
}

#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct FfiFileHit {
        path_rel: String,
        score: u32,
        /// 0 = Regular, 1 = Directory, 2 = Symlink. Lets the palette pick a
        /// folder vs document icon without re-stat'ing the path.
        kind_raw: u8,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct FfiSymbolHit {
        path_rel: String,
        name: String,
        kind_raw: u8,
        line: u32,
    }

    extern "Rust" {
        type FileHitList;

        fn len(&self) -> usize;
        fn at(&self, index: usize) -> FfiFileHit;
    }

    extern "Rust" {
        type SymbolHitList;

        fn len(&self) -> usize;
        fn at(&self, index: usize) -> FfiSymbolHit;
    }

    extern "Rust" {
        fn ffi_index_open(root: String) -> u64;
        fn ffi_index_close(handle: u64);
        fn ffi_index_query_fuzzy(handle: u64, query: String, limit: u32) -> FileHitList;
        fn ffi_index_query_symbols(handle: u64, query: String, limit: u32) -> SymbolHitList;
        fn ffi_index_query_git_dirty(handle: u64) -> FileHitList;
    }
}

pub struct FileHitList {
    hits: Vec<ffi::FfiFileHit>,
}

impl FileHitList {
    fn len(&self) -> usize {
        self.hits.len()
    }
    /// Returns an empty hit if `index >= len()`. The palette can race a
    /// stale index against a live refresh — degrade gracefully instead of
    /// aborting the host process.
    fn at(&self, index: usize) -> ffi::FfiFileHit {
        if index >= self.hits.len() {
            return ffi::FfiFileHit {
                path_rel: String::new(),
                score: 0,
                kind_raw: 0,
            };
        }
        let h = &self.hits[index];
        ffi::FfiFileHit {
            path_rel: h.path_rel.clone(),
            score: h.score,
            kind_raw: h.kind_raw,
        }
    }
}

pub struct SymbolHitList {
    hits: Vec<ffi::FfiSymbolHit>,
}

impl SymbolHitList {
    fn len(&self) -> usize {
        self.hits.len()
    }
    /// Returns an empty hit if `index >= len()`. See `FileHitList::at` for
    /// rationale — never panic across the FFI boundary on stale indices.
    fn at(&self, index: usize) -> ffi::FfiSymbolHit {
        if index >= self.hits.len() {
            return ffi::FfiSymbolHit {
                path_rel: String::new(),
                name: String::new(),
                kind_raw: 0,
                line: 0,
            };
        }
        let h = &self.hits[index];
        ffi::FfiSymbolHit {
            path_rel: h.path_rel.clone(),
            name: h.name.clone(),
            kind_raw: h.kind_raw,
            line: h.line,
        }
    }
}

pub fn ffi_index_open(root: String) -> u64 {
    let root_p = PathBuf::from(&root);
    let db_path = cache_path_for(&root_p);
    let (shared, is_new) = {
        let mut reg = registry().lock().unwrap();
        if let Some(existing) = reg.roots.get(&root_p).and_then(Weak::upgrade) {
            (existing, false)
        } else {
            reg.roots.remove(&root_p);
            let store = match IndexStore::open(&db_path) {
                Ok(s) => Arc::new(s),
                Err(e) => {
                    eprintln!("cairn: ffi_index_open failed for {root:?} (db {db_path:?}): {e}");
                    return 0;
                }
            };
            let shared = Arc::new(SharedIndex::new(store, root_p.clone()));
            reg.roots.insert(root_p.clone(), Arc::downgrade(&shared));
            (shared, true)
        }
    };

    if is_new {
        // Phase 1: walk + commit files. Fast — one fsync for the whole walk.
        let source_files = match walk_into(&root_p, &shared.store) {
            Ok((_, srcs)) => srcs,
            Err(_) => Vec::new(),
        };

        // Phase 2: tree-sitter symbol extraction off the critical path. The
        // file index is already queryable; symbol search (`@`) starts working
        // once this finishes (a few seconds for a typical project, longer on
        // huge roots — never blocks the UI).
        let shared_for_symbols = shared.clone();
        std::thread::spawn(move || {
            // Flush in chunks so the redb write lock isn't held for the whole
            // project. Without this, a large repo (~admin-app w/ thousands of
            // .ts files) can starve the watcher's writes long enough that the
            // app appears to freeze. 256 was chosen empirically: large enough
            // that fsync-per-batch cost is amortised, small enough that lock
            // hold time stays under ~50ms even on slow disks.
            const CHUNK: usize = 256;
            let mut buf: Vec<(String, Vec<cairn_index::SymbolRow>)> = Vec::with_capacity(CHUNK);
            for (rel, abs) in source_files {
                let syms = cairn_index::symbols::extract_from_file(&abs);
                if !syms.is_empty() {
                    buf.push((rel, syms));
                }
                if buf.len() >= CHUNK {
                    let _ = shared_for_symbols.store.bulk_put_symbols(&buf);
                    buf.clear();
                }
            }
            if !buf.is_empty() {
                let _ = shared_for_symbols.store.bulk_put_symbols(&buf);
            }
        });

        shared.set_watcher(watch(&root_p, shared.store.clone()).ok());
        shared.mark_ready();
    } else {
        // Another Tab is already opening this root. Wait until its initial
        // walk has populated the file table so this handle behaves like a
        // normal ready IndexService instead of returning empty results.
        shared.wait_until_ready();
    }

    let id = next_id();
    registry().lock().unwrap().handles.insert(id, shared);
    id
}

pub fn ffi_index_close(handle: u64) {
    registry().lock().unwrap().handles.remove(&handle);
}

pub fn ffi_index_query_fuzzy(handle: u64, query: String, limit: u32) -> FileHitList {
    let reg = registry().lock().unwrap();
    let entry = match reg.handles.get(&handle) {
        Some(e) => e,
        None => return FileHitList { hits: Vec::new() },
    };
    let hits = query_fuzzy(&entry.store, &query, limit as usize).unwrap_or_default();
    let mapped: Vec<ffi::FfiFileHit> = hits
        .into_iter()
        .map(|h| ffi::FfiFileHit {
            path_rel: h.path_rel,
            score: h.score,
            kind_raw: h.kind,
        })
        .collect();
    FileHitList { hits: mapped }
}

pub fn ffi_index_query_symbols(handle: u64, query: String, limit: u32) -> SymbolHitList {
    let reg = registry().lock().unwrap();
    let entry = match reg.handles.get(&handle) {
        Some(e) => e,
        None => return SymbolHitList { hits: Vec::new() },
    };
    let rows = entry
        .store
        .query_symbols(&query, limit as usize)
        .unwrap_or_default();
    let mapped: Vec<ffi::FfiSymbolHit> = rows
        .into_iter()
        .map(|(p, s)| ffi::FfiSymbolHit {
            path_rel: p,
            name: s.name,
            kind_raw: s.kind as u8,
            line: s.line,
        })
        .collect();
    SymbolHitList { hits: mapped }
}

pub fn ffi_index_query_git_dirty(handle: u64) -> FileHitList {
    let reg = registry().lock().unwrap();
    let entry = match reg.handles.get(&handle) {
        Some(e) => e,
        None => return FileHitList { hits: Vec::new() },
    };
    let snap = match cairn_git::snapshot(&entry.root) {
        Some(s) => s,
        None => return FileHitList { hits: Vec::new() },
    };
    let mut out = Vec::new();
    for p in snap
        .modified
        .iter()
        .chain(snap.untracked.iter())
        .chain(snap.added.iter())
        .chain(snap.deleted.iter())
    {
        out.push(ffi::FfiFileHit {
            path_rel: p.to_string_lossy().into_owned(),
            score: 0,
            kind_raw: 0,
        });
    }
    FileHitList { hits: out }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_root(name: &str) -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("cairn-ffi-{name}-{suffix}"));
        fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn index_open_allows_multiple_handles_for_same_root() {
        let root = temp_root("shared-index");
        fs::write(root.join("needle.txt"), "x").unwrap();
        let db_path = cache_path_for(&root);

        let first = ffi_index_open(root.to_string_lossy().into_owned());
        let second = ffi_index_open(root.to_string_lossy().into_owned());

        if first != 0 {
            ffi_index_close(first);
        }
        if second != 0 {
            ffi_index_close(second);
        }
        let _ = fs::remove_dir_all(&root);
        let _ = fs::remove_file(db_path);

        assert_ne!(first, 0, "first index open should succeed");
        assert_ne!(
            second, 0,
            "second index open for the same root should share the live index"
        );
    }
}

// ---- content session ----

struct ContentSession {
    search: ContentSearch,
    rx: Receiver<cairn_index::ContentHit>,
}

static CONTENT_SESSIONS: OnceLock<Mutex<HashMap<u64, ContentSession>>> = OnceLock::new();

fn content_sessions() -> &'static Mutex<HashMap<u64, ContentSession>> {
    CONTENT_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[swift_bridge::bridge]
mod ffi_content {
    #[swift_bridge(swift_repr = "struct")]
    struct FfiContentHit {
        path_rel: String,
        line: u32,
        preview: String,
    }

    extern "Rust" {
        type ContentHitList;

        fn len(&self) -> usize;
        fn at(&self, index: usize) -> FfiContentHit;
    }

    extern "Rust" {
        fn ffi_content_start(handle: u64, pattern: String, is_regex: bool) -> u64;
        fn ffi_content_poll(session: u64, max: u32) -> ContentHitList;
        fn ffi_content_cancel(session: u64);
    }
}

pub struct ContentHitList {
    hits: Vec<ffi_content::FfiContentHit>,
}

impl ContentHitList {
    fn len(&self) -> usize {
        self.hits.len()
    }
    /// Returns an empty hit if `index >= len()`. Content polls drain a
    /// background channel — Swift can hold a stale `len` snapshot just long
    /// enough for a race; bounds-check rather than panic.
    fn at(&self, index: usize) -> ffi_content::FfiContentHit {
        if index >= self.hits.len() {
            return ffi_content::FfiContentHit {
                path_rel: String::new(),
                line: 0,
                preview: String::new(),
            };
        }
        let h = &self.hits[index];
        ffi_content::FfiContentHit {
            path_rel: h.path_rel.clone(),
            line: h.line,
            preview: h.preview.clone(),
        }
    }
}

pub fn ffi_content_start(handle: u64, pattern: String, is_regex: bool) -> u64 {
    let rg_path = match std::env::var("CAIRN_RG_PATH") {
        Ok(p) => PathBuf::from(p),
        Err(_) => match which::which("rg") {
            Ok(p) => p,
            Err(_) => return 0,
        },
    };
    let root = {
        let reg = registry().lock().unwrap();
        match reg.handles.get(&handle) {
            Some(e) => e.root.clone(),
            None => return 0,
        }
    };
    let (tx, rx): (Sender<_>, Receiver<_>) = channel();
    let search = ContentSearch::spawn(&rg_path, &root, &pattern, is_regex, move |hit| {
        let _ = tx.send(hit);
    });
    let id = next_id();
    content_sessions()
        .lock()
        .unwrap()
        .insert(id, ContentSession { search, rx });
    id
}

pub fn ffi_content_poll(session: u64, max: u32) -> ContentHitList {
    let mut out = Vec::new();
    let sessions = content_sessions().lock().unwrap();
    if let Some(s) = sessions.get(&session) {
        while out.len() < max as usize {
            match s.rx.try_recv() {
                Ok(hit) => out.push(ffi_content::FfiContentHit {
                    path_rel: hit.path_rel,
                    line: hit.line,
                    preview: hit.preview,
                }),
                Err(_) => break,
            }
        }
    }
    ContentHitList { hits: out }
}

pub fn ffi_content_cancel(session: u64) {
    // Remove + drop the session OUTSIDE the global mutex. `ContentSession`
    // owns a `ContentSearch` whose `Drop` joins the worker thread; the join
    // can take tens of ms while the worker observes the cancel flag and
    // tears down the rg child. Holding `CONTENT_SESSIONS` through that join
    // blocks the main-thread `ffi_content_poll` timer (and any new
    // `ffi_content_start`) for the same window — visible as palette stalls
    // when the user retypes a query mid-search. Signal cancel synchronously
    // (cheap, just an atomic store), then release the lock and let `Drop`
    // do the join unobstructed.
    let removed = {
        let mut sessions = content_sessions().lock().unwrap();
        sessions.remove(&session)
    };
    if let Some(mut s) = removed {
        s.search.cancel();
        drop(s); // explicit for clarity — joins the worker here.
    }
}
