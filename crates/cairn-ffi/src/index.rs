use cairn_index::{
    cache_path_for, query_fuzzy, walk_into, watch, ContentSearch, IndexStore, Watcher,
};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex, OnceLock};

struct HandleEntry {
    store: Arc<IndexStore>,
    _watcher: Option<Watcher>,
    root: PathBuf,
}

static REGISTRY: OnceLock<Mutex<HashMap<u64, HandleEntry>>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<u64>> = OnceLock::new();

fn registry() -> &'static Mutex<HashMap<u64, HandleEntry>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
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
    fn at(&self, index: usize) -> ffi::FfiFileHit {
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
    fn at(&self, index: usize) -> ffi::FfiSymbolHit {
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
    let store = match IndexStore::open(&db_path) {
        Ok(s) => Arc::new(s),
        Err(e) => {
            eprintln!("cairn: ffi_index_open failed for {root:?} (db {db_path:?}): {e}");
            return 0;
        }
    };
    // Phase 1: walk + commit files. Fast — one fsync for the whole walk.
    let source_files = match walk_into(&root_p, &store) {
        Ok((_, srcs)) => srcs,
        Err(_) => Vec::new(),
    };

    // Phase 2: tree-sitter symbol extraction off the critical path. The
    // file index is already queryable; symbol search (`@`) starts working
    // once this finishes (a few seconds for a typical project, longer on
    // huge roots — never blocks the UI).
    let store_for_symbols = store.clone();
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
                let _ = store_for_symbols.bulk_put_symbols(&buf);
                buf.clear();
            }
        }
        if !buf.is_empty() {
            let _ = store_for_symbols.bulk_put_symbols(&buf);
        }
    });

    let watcher = watch(&root_p, store.clone()).ok();
    let id = next_id();
    registry().lock().unwrap().insert(
        id,
        HandleEntry {
            store,
            _watcher: watcher,
            root: root_p,
        },
    );
    id
}

pub fn ffi_index_close(handle: u64) {
    registry().lock().unwrap().remove(&handle);
}

pub fn ffi_index_query_fuzzy(handle: u64, query: String, limit: u32) -> FileHitList {
    let reg = registry().lock().unwrap();
    let entry = match reg.get(&handle) {
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
    let entry = match reg.get(&handle) {
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
    let entry = match reg.get(&handle) {
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
    fn at(&self, index: usize) -> ffi_content::FfiContentHit {
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
        match reg.get(&handle) {
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
    let mut sessions = content_sessions().lock().unwrap();
    if let Some(mut s) = sessions.remove(&session) {
        s.search.cancel();
    }
}
