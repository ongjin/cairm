use cairn_index::{IndexStore, walk_into, query_fuzzy, cache_path_for, Watcher, watch, ContentSearch};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver, Sender};

struct HandleEntry {
    store: Arc<IndexStore>,
    _watcher: Option<Watcher>,
    root: PathBuf,
}

static REGISTRY: OnceLock<Mutex<HashMap<u64, HandleEntry>>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<u64>> = OnceLock::new();

fn registry() -> &'static Mutex<HashMap<u64, HandleEntry>> { REGISTRY.get_or_init(|| Mutex::new(HashMap::new())) }
fn next_id() -> u64 { let m = NEXT_ID.get_or_init(|| Mutex::new(1)); let mut g = m.lock().unwrap(); let id = *g; *g += 1; id }

#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct FfiFileHit {
        path_rel: String,
        score: u32,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct FfiSymbolHit {
        path_rel: String,
        name: String,
        kind_raw: u8,
        line: u32,
    }

    extern "Rust" {
        fn ffi_index_open(root: String) -> u64;
        fn ffi_index_close(handle: u64);
        fn ffi_index_query_fuzzy(handle: u64, query: String, limit: u32) -> Vec<FfiFileHit>;
        fn ffi_index_query_symbols(handle: u64, query: String, limit: u32) -> Vec<FfiSymbolHit>;
        fn ffi_index_query_git_dirty(handle: u64) -> Vec<FfiFileHit>;
    }
}

pub fn ffi_index_open(root: String) -> u64 {
    let root_p = PathBuf::from(&root);
    let db_path = cache_path_for(&root_p);
    let store = match IndexStore::open(&db_path) { Ok(s) => Arc::new(s), Err(_) => return 0 };
    let _ = walk_into(&root_p, &store);
    let watcher = watch(&root_p, store.clone()).ok();
    let id = next_id();
    registry().lock().unwrap().insert(id, HandleEntry { store, _watcher: watcher, root: root_p });
    id
}

pub fn ffi_index_close(handle: u64) {
    registry().lock().unwrap().remove(&handle);
}

pub fn ffi_index_query_fuzzy(handle: u64, query: String, limit: u32) -> Vec<ffi::FfiFileHit> {
    let reg = registry().lock().unwrap();
    let entry = match reg.get(&handle) { Some(e) => e, None => return Vec::new() };
    let hits = query_fuzzy(&entry.store, &query, limit as usize).unwrap_or_default();
    hits.into_iter().map(|h| ffi::FfiFileHit { path_rel: h.path_rel, score: h.score }).collect()
}

pub fn ffi_index_query_symbols(handle: u64, query: String, limit: u32) -> Vec<ffi::FfiSymbolHit> {
    let reg = registry().lock().unwrap();
    let entry = match reg.get(&handle) { Some(e) => e, None => return Vec::new() };
    let rows = entry.store.query_symbols(&query, limit as usize).unwrap_or_default();
    rows.into_iter().map(|(p, s)| ffi::FfiSymbolHit {
        path_rel: p,
        name: s.name,
        kind_raw: s.kind as u8,
        line: s.line,
    }).collect()
}

pub fn ffi_index_query_git_dirty(handle: u64) -> Vec<ffi::FfiFileHit> {
    let reg = registry().lock().unwrap();
    let entry = match reg.get(&handle) { Some(e) => e, None => return Vec::new() };
    let snap = match cairn_git::snapshot(&entry.root) { Some(s) => s, None => return Vec::new() };
    let mut out = Vec::new();
    for p in snap.modified.iter().chain(snap.untracked.iter()).chain(snap.added.iter()).chain(snap.deleted.iter()) {
        out.push(ffi::FfiFileHit { path_rel: p.to_string_lossy().into_owned(), score: 0 });
    }
    out
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
        fn ffi_content_start(handle: u64, pattern: String) -> u64;
        fn ffi_content_poll(session: u64, max: u32) -> Vec<FfiContentHit>;
        fn ffi_content_cancel(session: u64);
    }
}

pub fn ffi_content_start(handle: u64, pattern: String) -> u64 {
    let rg_path = match std::env::var("CAIRN_RG_PATH") {
        Ok(p) => PathBuf::from(p),
        Err(_) => match which::which("rg") { Ok(p) => p, Err(_) => return 0 },
    };
    let root = {
        let reg = registry().lock().unwrap();
        match reg.get(&handle) { Some(e) => e.root.clone(), None => return 0 }
    };
    let (tx, rx): (Sender<_>, Receiver<_>) = channel();
    let search = ContentSearch::spawn(&rg_path, &root, &pattern, move |hit| { let _ = tx.send(hit); });
    let id = next_id();
    content_sessions().lock().unwrap().insert(id, ContentSession { search, rx });
    id
}

pub fn ffi_content_poll(session: u64, max: u32) -> Vec<ffi_content::FfiContentHit> {
    let mut out = Vec::new();
    let sessions = content_sessions().lock().unwrap();
    if let Some(s) = sessions.get(&session) {
        while out.len() < max as usize {
            match s.rx.try_recv() {
                Ok(hit) => out.push(ffi_content::FfiContentHit { path_rel: hit.path_rel, line: hit.line, preview: hit.preview }),
                Err(_) => break,
            }
        }
    }
    out
}

pub fn ffi_content_cancel(session: u64) {
    let mut sessions = content_sessions().lock().unwrap();
    if let Some(mut s) = sessions.remove(&session) { s.search.cancel(); }
}
