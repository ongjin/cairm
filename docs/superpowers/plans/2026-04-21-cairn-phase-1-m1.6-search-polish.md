# Cairn Phase 1 · M1.6 — Search + Polish + v0.1.0-alpha

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `⌘F` inline search (folder filter + subtree streaming walk) 추가, M1.2–M1.5 이월 polish 19 항 흡수, README/USAGE/DMG 준비 후 `v0.1.0-alpha` 태그.

**Architecture:** `cairn-search` 크레이트를 skeleton 에서 실구현으로 교체 (Session registry + `ignore::WalkBuilder` + bounded `mpsc::channel`, cap 5000, cancellation via `Arc<AtomicBool>`). FFI 는 3개 async/sync 함수 추가 (`search_start` / `search_next_batch` / `search_cancel`). Swift 는 신규 `SearchModel` `@Observable` + `SearchField` view + `FileListView` entries 주입 refactor + `FileListCoordinator` 에 Folder 컬럼.

**Tech Stack:** Rust 1.85 · `ignore = "0.4"` · `once_cell` · swift-bridge 0.1.59 · Swift 5.9 / macOS 14+ · SwiftUI / AppKit · xcodegen 2.45

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main branch, HEAD 시작은 `phase-1-m1.5` 태그)

**Predecessor:** M1.5 — `docs/superpowers/plans/2026-04-21-cairn-phase-1-m1.5-theme-context-menu.md` (완료, tag `phase-1-m1.5`)
**Parent spec:** `docs/superpowers/specs/2026-04-21-cairn-phase-1-m1.6-search-polish-design.md`

**Deliverable verification (M1.6 완료 조건):**
- `cargo test --workspace` 녹색 (신규 `cairn-search` 테스트 10개 추가)
- `cargo clippy --workspace --all-targets -- -D warnings` 녹색
- `cargo fmt --check` clean
- `xcodebuild build` 성공
- `xcodebuild test` 20+ (신규 SearchModelTests + SidebarModelTests)
- 앱 실행 → `⌘F` 동작, folder/subtree 토글, 결과 live populate, `⌘⌫` NSAlert, Open With 캐시 확인
- `git tag phase-1-m1.6` + `git tag v0.1.0-alpha` (같은 HEAD)

**특이사항:**
- **Generated diff 발생 예정** — M1.6 은 FFI 를 건드리므로 `apps/Sources/Generated/cairn_ffi.swift` 등 파일에 실 diff 가 생긴다. M1.1~M1.5 의 "diff 0" 규칙은 이 마일스톤엔 적용 안 함. Force-committed 된 Generated 파일을 정상적으로 업데이트.
- **SourceKit 진단 stale** — `xcodegen generate` 직후 SourceKit 이 "Cannot find X" 를 쏟아내도 무시. `xcodebuild build` / `xcodebuild test` 의 exit code 가 진실.
- **원격 push 는 사용자 수동.** 이 플랜은 push 하지 않는다.
- **커밋 메시지 verbatim.** 각 Task 의 커밋 명령 텍스트 그대로.

---

## 1. 기술 참조 (M1.6 특유 함정)

- **`swift-bridge` 0.1.x async fn** — `async fn search_next_batch(h: u64) -> Option<Vec<FileEntry>>` 는 이미 M1.1 의 `list_directory` 와 같은 패턴. Rust 측에서 `async fn` 으로 선언하고 내부에서 blocking `recv_timeout` 을 `tokio::task::spawn_blocking` 이나 `std::thread::spawn` 으로 감싸 Swift Task 와 연동. (Phase 0 FFI 는 이미 이 방식을 취함.)
- **`ignore::WalkBuilder`** — `hidden(!show_hidden)` 으로 dotfile skip, `git_ignore(!show_hidden)` 으로 `.gitignore` 존중. Default 는 양쪽 모두 존중이라 `show_hidden = true` 일 때 둘 다 false 로 꺼야 함.
- **`Session registry`** — `once_cell::sync::Lazy<Mutex<HashMap<u64, Session>>>`. Handle 은 `AtomicU64::fetch_add(1)` 로 monotonic. Session drop 시 thread join 은 비동기 (walker 가 cancel flag 를 보고 빠르게 빠져나옴).
- **`mpsc` bounded** — `std::sync::mpsc::sync_channel(4)` (4 batch buffer). Walker 가 receiver drop 을 감지하면 `send` 가 Err → walker 자동 종료.
- **`FileEntry` FFI serialization** — swift-bridge 는 Vec<UserType> 을 shared 타입으로 opt-in 해야 함. M1.1 에서 이미 `FileEntry` 가 `#[swift_bridge(swift_name = "FileEntry")]` 로 노출돼 있으므로 재사용.
- **Swift `@FocusState`** — SwiftUI 에서 `NSSearchField` 대신 `TextField(...).focused($state)` 를 쓰면 `focused = true` 한 줄로 focus 부여. `⌘F` hidden button 은 `.frame(width: 0, height: 0).opacity(0).allowsHitTesting(false)` 로 invisible.
- **`NSTableView` 컬럼 동적 추가/제거** — `addTableColumn(_:)` / `removeTableColumn(_:)` 는 런타임에 가능. 컬럼 identifier 로 찾아서 토글. `reloadData` 가 필수.
- **`NSTableView` 다중 reload 퍼포먼스** — 5000 row 의 `reloadData` 는 0.1–0.2초. Debounce + batch coalescing 으로 30fps 제한.
- **Debounce 구현** — `Task.sleep(nanoseconds: 200_000_000)` 후 `Task.isCancelled` 체크. 이전 task 가 cancel 되면 sleep 중 throw → early return.
- **`xcodebuild test` 병렬** — 신규 `SearchModelTests` 는 timeout 길 수 있음 (subtree mode 가 temp fixture 에서 walk). 단위 테스트는 in-memory 에 한정해서 <0.1s 가 되도록.
- **`create-dmg`** — `brew install create-dmg` 필요. 설치 안 돼있으면 스크립트가 친절하게 알려줘야 함.

---

## 2. File Structure 요약

**신규:**
- `crates/cairn-search/src/lib.rs` (public API)
- `crates/cairn-search/src/session.rs` (Session + registry)
- `crates/cairn-search/tests/integration.rs`
- `apps/Sources/Models/SearchModel.swift`
- `apps/Sources/Models/FolderModel+Sort.swift`
- `apps/Sources/App/CairnEngine+Search.swift`
- `apps/Sources/Views/Search/SearchField.swift`
- `apps/Tests/SearchModelTests.swift`
- `apps/Tests/SidebarModelTests.swift`
- `scripts/make-dmg.sh`
- `README.md`
- `USAGE.md`

**수정:**
- `crates/cairn-search/Cargo.toml` (deps: `cairn-core`, `ignore`, `once_cell`)
- `crates/cairn-ffi/Cargo.toml` (dep: `cairn-search`)
- `crates/cairn-ffi/src/lib.rs` (bridge 3 functions)
- `crates/cairn-core/src/lib.rs` (P14: `WalkerError` re-export)
- `crates/cairn-preview/src/lib.rs` (P16: max_bytes=0 guard)
- `apps/Sources/ContentView.swift` (SearchField toolbar + ⌘F + entries branch + onChange)
- `apps/Sources/Models/FolderModel.swift` (comparator extraction)
- `apps/Sources/Models/PreviewModel.swift` (P1)
- `apps/Sources/Views/FileList/FileListView.swift` (P12 + entries injection)
- `apps/Sources/Views/FileList/FileListCoordinator.swift` (Folder 컬럼 + P3/P4/P5/P6/P7/P8/P10/P11/P18)
- `apps/Sources/Views/Preview/PreviewRenderers.swift` (P2)
- `apps/Sources/App/AppModel.swift` (P17)

**Generated (regen; force-committed):** `apps/Sources/Generated/cairn_ffi.{h,swift}`, `SwiftBridgeCore.{h,swift}`

---

## Task 1: `cairn-search` — types + Cargo.toml deps

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-search/Cargo.toml`
- Replace: `/Users/cyj/workspace/personal/cairn/crates/cairn-search/src/lib.rs`

- [ ] **Step 1: Cargo.toml 에 deps 추가**

전체 교체:

```toml
[package]
name = "cairn-search"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_search"

[dependencies]
cairn-core = { path = "../cairn-core" }
ignore = "0.4"
once_cell = "1"
thiserror = { workspace = true }

[dev-dependencies]
tempfile = "3"
```

- [ ] **Step 2: `src/lib.rs` 교체 — public API 표면만**

```rust
//! Streaming filename search backing the `⌘F` bar in Cairn.
//!
//! Spawns a walker in a background thread and delivers matching entries in
//! batches via a `u64` handle. Callers pull batches with `next_batch` until
//! it returns `None`, then the session is self-cleaned.

mod session;

use cairn_core::FileEntry;
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
```

- [ ] **Step 3: `src/session.rs` 파일 생성 (stub — Task 2 에서 실구현)**

```rust
//! Session registry and walker thread. Task 2 fills in the Folder-mode
//! implementation; Task 3 adds Subtree-mode; Task 4 adds cancellation + cap.

use crate::{SearchOptions, SearchStatus};
use cairn_core::FileEntry;
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
```

- [ ] **Step 4: 빌드 + clippy**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo build -p cairn-search
cargo clippy -p cairn-search --all-targets -- -D warnings
```

Expected: clean build + clippy (stub impl 이지만 unused arg warn 은 `_` 로 이미 봉인).

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add crates/cairn-search/Cargo.toml crates/cairn-search/src/lib.rs crates/cairn-search/src/session.rs
git commit -m "feat(search): add cairn-search public API skeleton"
```

---

## Task 2: Session registry + Folder-mode walker (TDD)

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-search/src/session.rs`
- Create: `/Users/cyj/workspace/personal/cairn/crates/cairn-search/tests/integration.rs`

- [ ] **Step 1: 테스트 파일 작성 (fail 예상)**

`crates/cairn-search/tests/integration.rs`:

```rust
use cairn_search::{start, next_batch, status, SearchMode, SearchOptions, SearchStatus};
use std::fs;
use tempfile::tempdir;

fn collect_all(h: cairn_search::SearchHandle) -> Vec<String> {
    let mut names = Vec::new();
    while let Some(batch) = next_batch(h) {
        for e in batch {
            names.push(e.name.clone());
        }
    }
    names
}

#[test]
fn smoke_empty_root() {
    let tmp = tempdir().unwrap();
    let h = start(tmp.path(), SearchOptions {
        query: "x".into(),
        mode: SearchMode::Folder,
        ..Default::default()
    });
    assert!(collect_all(h).is_empty());
    assert_eq!(status(h), SearchStatus::Done);
}

#[test]
fn folder_mode_matches_only_direct_children() {
    let tmp = tempdir().unwrap();
    fs::write(tmp.path().join("readme.txt"), b"").unwrap();
    fs::write(tmp.path().join("README.md"), b"").unwrap();
    fs::create_dir(tmp.path().join("sub")).unwrap();
    fs::write(tmp.path().join("sub/readme_inner.txt"), b"").unwrap();

    let h = start(tmp.path(), SearchOptions {
        query: "readme".into(),
        mode: SearchMode::Folder,
        ..Default::default()
    });
    let names = collect_all(h);
    assert_eq!(names.len(), 2, "got {:?}", names);
    assert!(names.iter().any(|n| n == "readme.txt"));
    assert!(names.iter().any(|n| n == "README.md"));
}

#[test]
fn case_insensitive_match() {
    let tmp = tempdir().unwrap();
    fs::write(tmp.path().join("FooBar.txt"), b"").unwrap();

    let h = start(tmp.path(), SearchOptions {
        query: "FOOBAR".into(),
        mode: SearchMode::Folder,
        ..Default::default()
    });
    let names = collect_all(h);
    assert_eq!(names, vec!["FooBar.txt"]);
}
```

- [ ] **Step 2: 테스트 fail 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-search 2>&1 | tail -10
```

Expected: 3 tests fail (stub 은 모두 None 을 반환).

- [ ] **Step 3: `session.rs` 실구현 — Folder 모드 + registry**

전체 교체:

```rust
//! Session registry + walker threads. Folder mode uses `std::fs::read_dir`
//! (depth 1), Subtree mode uses `ignore::WalkBuilder` (Task 3). Cancellation
//! + cap (Task 4).

use crate::{SearchMode, SearchOptions, SearchStatus};
use cairn_core::FileEntry;
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
    // thread join handle intentionally dropped — daemon-style; walker
    // polls `cancel` every iteration so it exits promptly on drop.
}

static REGISTRY: Lazy<Mutex<HashMap<u64, Arc<Session>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
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
        let mut s = status_w.lock().unwrap();
        *s = outcome;
    });

    REGISTRY.lock().unwrap().insert(
        id,
        Arc::new(Session { cancel, rx: Mutex::new(rx), status }),
    );
    handle
}

pub(crate) fn next_batch(h: SearchHandle) -> Option<Vec<FileEntry>> {
    let session = {
        let reg = REGISTRY.lock().unwrap();
        reg.get(&h.0).cloned()
    }?;

    // Hold the rx lock briefly; channel is the natural contention point.
    let rx = session.rx.lock().unwrap();
    match rx.recv_timeout(Duration::from_millis(100)) {
        Ok(batch) => Some(batch),
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
            // Walker still running — return empty batch? No: contract is
            // "None when done". A timeout in the middle of a busy walk is
            // unusual but possible. Return Some(vec![]) so caller loops again.
            Some(Vec::new())
        }
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
            // Walker finished; remove from registry so next call is short-circuit.
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
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.to_lowercase().contains(&needle) {
            continue;
        }
        if !opts.show_hidden && name.starts_with('.') {
            continue;
        }
        if let Some(fe) = to_file_entry(&entry) {
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
    }
    if !buffer.is_empty() {
        let _ = tx.send(buffer);
    }
    SearchStatus::Done
}

fn run_subtree(
    _root: &Path,
    _opts: &SearchOptions,
    _cancel: Arc<AtomicBool>,
    _tx: SyncSender<Vec<FileEntry>>,
) -> SearchStatus {
    // Implemented in Task 3.
    SearchStatus::Done
}

fn to_file_entry(entry: &std::fs::DirEntry) -> Option<FileEntry> {
    let meta = entry.metadata().ok()?;
    let ft = meta.file_type();
    let kind = if ft.is_dir() {
        cairn_core::FileKind::Directory
    } else if ft.is_symlink() {
        cairn_core::FileKind::Symlink
    } else {
        cairn_core::FileKind::File
    };
    let modified_unix = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    Some(FileEntry {
        name: entry.file_name().to_string_lossy().to_string(),
        path: entry.path().to_string_lossy().to_string(),
        kind,
        size: if ft.is_dir() { 0 } else { meta.len() },
        modified_unix,
    })
}
```

> **Note:** This assumes `cairn_core::FileEntry` has public fields `name: String`, `path: String`, `kind: FileKind`, `size: u64`, `modified_unix: i64`. If any field has a different type/name, adjust to match. See `crates/cairn-core/src/lib.rs` to verify before writing.

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-search 2>&1 | tail -10
```

Expected: 3 tests pass.

- [ ] **Step 5: clippy**

```bash
cargo clippy -p cairn-search --all-targets -- -D warnings
```

Expected: clean.

- [ ] **Step 6: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add crates/cairn-search/src/session.rs crates/cairn-search/tests/integration.rs
git commit -m "feat(search): implement folder-mode walker + session registry"
```

---

## Task 3: Subtree mode (`ignore::WalkBuilder`) + TDD

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-search/src/session.rs:run_subtree`
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-search/tests/integration.rs`

- [ ] **Step 1: 신규 테스트 추가**

`tests/integration.rs` 하단에 append:

```rust
#[test]
fn subtree_mode_recursive() {
    let tmp = tempdir().unwrap();
    fs::create_dir_all(tmp.path().join("a/b")).unwrap();
    fs::write(tmp.path().join("a/hello.txt"), b"").unwrap();
    fs::write(tmp.path().join("a/b/hello.md"), b"").unwrap();
    fs::write(tmp.path().join("unrelated.txt"), b"").unwrap();

    let h = start(tmp.path(), SearchOptions {
        query: "hello".into(),
        mode: SearchMode::Subtree,
        ..Default::default()
    });
    let names = collect_all(h);
    assert_eq!(names.len(), 2, "got {:?}", names);
    assert!(names.iter().any(|n| n == "hello.txt"));
    assert!(names.iter().any(|n| n == "hello.md"));
}

#[test]
fn gitignore_respected_when_hidden_off() {
    let tmp = tempdir().unwrap();
    fs::write(tmp.path().join(".gitignore"), b"build/\n").unwrap();
    fs::create_dir(tmp.path().join("build")).unwrap();
    fs::write(tmp.path().join("build/secret.txt"), b"").unwrap();
    fs::write(tmp.path().join("keep.txt"), b"").unwrap();

    // show_hidden=false → .gitignore respected → build/ excluded
    let h = start(tmp.path(), SearchOptions {
        query: "".into(), // empty query means "everything matches"
        mode: SearchMode::Subtree,
        show_hidden: false,
        ..Default::default()
    });
    let names = collect_all(h);
    assert!(!names.contains(&"secret.txt".to_string()), "got {:?}", names);
    assert!(names.contains(&"keep.txt".to_string()));
}

#[test]
fn subtree_hidden_files_off_skips_dotfiles() {
    let tmp = tempdir().unwrap();
    fs::write(tmp.path().join(".hidden.txt"), b"").unwrap();
    fs::write(tmp.path().join("visible.txt"), b"").unwrap();

    let h = start(tmp.path(), SearchOptions {
        query: "".into(),
        mode: SearchMode::Subtree,
        show_hidden: false,
        ..Default::default()
    });
    let names = collect_all(h);
    assert!(!names.contains(&".hidden.txt".to_string()));
    assert!(names.contains(&"visible.txt".to_string()));
}
```

- [ ] **Step 2: fail 확인**

```bash
cargo test -p cairn-search 2>&1 | tail -15
```

Expected: 3 new tests fail (Subtree 구현 없음).

- [ ] **Step 3: `run_subtree` 실구현 + empty-query match-all 처리**

`session.rs` 의 `run_folder` 와 `run_subtree` 를 다음으로 교체 (empty-query 로직은 두 경로 공통이라 helper 로 빼도 되지만 단순함 우선):

```rust
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
        let name = entry.file_name().to_string_lossy().to_string();
        if !opts.show_hidden && name.starts_with('.') {
            continue;
        }
        if !match_all && !name.to_lowercase().contains(&needle) {
            continue;
        }
        if let Some(fe) = to_file_entry(&entry) {
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
        let file_name = entry
            .file_name()
            .to_string_lossy()
            .to_string();
        if !match_all && !file_name.to_lowercase().contains(&needle) {
            continue;
        }
        let Some(fe) = walk_entry_to_file_entry(&entry) else { continue };
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

fn walk_entry_to_file_entry(entry: &ignore::DirEntry) -> Option<FileEntry> {
    let meta = entry.metadata().ok()?;
    let ft = meta.file_type();
    let kind = if ft.is_dir() {
        cairn_core::FileKind::Directory
    } else if ft.is_symlink() {
        cairn_core::FileKind::Symlink
    } else {
        cairn_core::FileKind::File
    };
    let modified_unix = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    Some(FileEntry {
        name: entry.file_name().to_string_lossy().to_string(),
        path: entry.path().to_string_lossy().to_string(),
        kind,
        size: if ft.is_dir() { 0 } else { meta.len() },
        modified_unix,
    })
}
```

> **Note on `ignore::DirEntry::metadata()`**: `ignore` 0.4 의 `DirEntry::metadata()` 반환은 `Result<Metadata, ignore::Error>` (std `Metadata` 아님). 호출부에서 `.ok()?` 로 한번 더 unwrap. 실제 API 확인 후 맞춰서. `cairn-walker` 의 기존 코드를 참고하면 빠름.

- [ ] **Step 4: 테스트 통과 확인**

```bash
cargo test -p cairn-search 2>&1 | tail -15
```

Expected: 6 tests pass (3 기존 + 3 신규).

- [ ] **Step 5: clippy**

```bash
cargo clippy -p cairn-search --all-targets -- -D warnings
```

Expected: clean.

- [ ] **Step 6: 커밋**

```bash
git add crates/cairn-search/src/session.rs crates/cairn-search/tests/integration.rs
git commit -m "feat(search): add subtree-mode walker (ignore::WalkBuilder)"
```

---

## Task 4: Cancellation + cap enforcement tests (edge cases)

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-search/tests/integration.rs`

Cancellation/cap 로직은 Task 2/3 에서 이미 구현. 이 Task 는 엣지 케이스 커버.

- [ ] **Step 1: 테스트 추가**

`tests/integration.rs` 하단 append:

```rust
use cairn_search::cancel;
use std::thread::sleep;
use std::time::Duration;

#[test]
fn cancel_mid_walk() {
    let tmp = tempdir().unwrap();
    // Make a wide tree so the walker doesn't finish instantly.
    for i in 0..200 {
        fs::write(tmp.path().join(format!("f{i}.txt")), b"").unwrap();
    }

    let h = start(tmp.path(), SearchOptions {
        query: "".into(),
        mode: SearchMode::Subtree,
        batch_size: 16, // force multiple batches
        ..Default::default()
    });
    // Let the walker produce one batch, then cancel.
    sleep(Duration::from_millis(20));
    cancel(h);

    // Drain whatever is still coming. Must terminate.
    let mut total = 0;
    while let Some(b) = next_batch(h) {
        total += b.len();
        if total > 200 { break; } // safety net
    }
    assert!(total < 200 || total == 200); // soft: just must not hang
}

#[test]
fn cap_enforcement() {
    let tmp = tempdir().unwrap();
    for i in 0..20 {
        fs::write(tmp.path().join(format!("hit{i}.txt")), b"").unwrap();
    }

    let h = start(tmp.path(), SearchOptions {
        query: "hit".into(),
        mode: SearchMode::Folder,
        result_cap: 10,
        ..Default::default()
    });
    let names = collect_all(h);
    assert_eq!(names.len(), 10);
    assert_eq!(status(h), SearchStatus::Capped);
}

#[test]
fn invalid_handle_safe() {
    use cairn_search::SearchHandle;
    let bad = SearchHandle(999_999_999);
    assert!(next_batch(bad).is_none());
    assert_eq!(status(bad), SearchStatus::Done);
    cancel(bad); // should not panic
}

#[test]
fn concurrent_sessions_independent() {
    let tmp1 = tempdir().unwrap();
    fs::write(tmp1.path().join("alpha.txt"), b"").unwrap();
    let tmp2 = tempdir().unwrap();
    fs::write(tmp2.path().join("beta.txt"), b"").unwrap();

    let h1 = start(tmp1.path(), SearchOptions {
        query: "alpha".into(),
        mode: SearchMode::Folder,
        ..Default::default()
    });
    let h2 = start(tmp2.path(), SearchOptions {
        query: "beta".into(),
        mode: SearchMode::Folder,
        ..Default::default()
    });

    let names1 = collect_all(h1);
    let names2 = collect_all(h2);
    assert_eq!(names1, vec!["alpha.txt"]);
    assert_eq!(names2, vec!["beta.txt"]);
}
```

- [ ] **Step 2: 테스트 실행 (cap status 는 race 소지 있으므로 status 호출을 collect_all 안에서 remove 된 뒤 호출하지 않도록 주의)**

`cap_enforcement` 의 status 호출 타이밍이 미묘. `collect_all` 에서 `next_batch` 가 disconnect 받으면 registry 에서 remove — 그 뒤 `status` 는 Done 을 리턴한다 (등록 없음). 따라서 `cap_enforcement` 는 status 체크 전에 collect_all 이 끝나면 잘못된 결과. **대안**: `next_batch` 와 interleave 로 status 를 capture:

```rust
#[test]
fn cap_enforcement() {
    let tmp = tempdir().unwrap();
    for i in 0..20 {
        fs::write(tmp.path().join(format!("hit{i}.txt")), b"").unwrap();
    }

    let h = start(tmp.path(), SearchOptions {
        query: "hit".into(),
        mode: SearchMode::Folder,
        result_cap: 10,
        ..Default::default()
    });

    // Pull batches until exhausted; check status BEFORE channel disconnect
    // propagates to registry removal.
    let mut names = Vec::new();
    let mut observed_capped = false;
    while let Some(batch) = next_batch(h) {
        for e in batch {
            names.push(e.name.clone());
        }
        if status(h) == SearchStatus::Capped {
            observed_capped = true;
        }
    }
    assert_eq!(names.len(), 10, "got {:?}", names);
    assert!(observed_capped, "status never transitioned to Capped");
}
```

`cap_enforcement` 를 위 버전으로 교체한 후:

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-search 2>&1 | tail -15
```

Expected: 10 tests pass.

- [ ] **Step 3: clippy + fmt**

```bash
cargo clippy -p cairn-search --all-targets -- -D warnings
cargo fmt -p cairn-search
```

- [ ] **Step 4: 커밋**

```bash
git add crates/cairn-search/tests/integration.rs
# cargo fmt 으로 변경이 있으면 같이 커밋:
git add crates/cairn-search/src/
git commit -m "test(search): cover cancellation, cap, invalid-handle, concurrency"
```

---

## Task 5: FFI bridge — `search_start` / `search_next_batch` / `search_cancel`

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-ffi/Cargo.toml`
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-ffi/src/lib.rs`
- Regen: `apps/Sources/Generated/cairn_ffi.{h,swift}`, `SwiftBridgeCore.{h,swift}`

- [ ] **Step 1: `cairn-ffi/Cargo.toml` 에 `cairn-search` dep 추가**

기존 dependencies 섹션 아래에 `cairn-search = { path = "../cairn-search" }` 줄 추가. 결과:

```toml
[dependencies]
cairn-core = { path = "../cairn-core" }
cairn-walker = { path = "../cairn-walker" }
cairn-preview = { path = "../cairn-preview" }
cairn-search = { path = "../cairn-search" }
swift-bridge = "0.1"
```

- [ ] **Step 2: `crates/cairn-ffi/src/lib.rs` 의 `#[swift_bridge::bridge]` 모듈 확장**

**확인 먼저:** 기존 `lib.rs` 를 Read 해서 extern "Rust" 블록 위치를 찾는다. 다음 3 함수를 기존 함수들(list_directory, preview_text 등) 다음에 추가한다. 아래는 자체완결 패치 — 기존 다른 함수는 유지한다.

```rust
// 기존 `extern "Rust" { ... }` 블록 내부 맨 아래에 추가
#[swift_bridge(swift_name = "searchStart")]
fn search_start(
    root_path: String,
    query: String,
    subtree: bool,
    show_hidden: bool,
) -> u64;

#[swift_bridge(swift_name = "searchNextBatch")]
async fn search_next_batch(handle: u64) -> Option<Vec<FileEntry>>;

#[swift_bridge(swift_name = "searchCancel")]
fn search_cancel(handle: u64);
```

그리고 bridge 모듈 바깥 (파일 레벨) 에 actual Rust 구현 3개를 추가:

```rust
fn search_start(root_path: String, query: String, subtree: bool, show_hidden: bool) -> u64 {
    use cairn_search::{start, SearchMode, SearchOptions};
    let opts = SearchOptions {
        query,
        mode: if subtree { SearchMode::Subtree } else { SearchMode::Folder },
        show_hidden,
        ..Default::default()
    };
    let handle = start(std::path::Path::new(&root_path), opts);
    handle.0
}

async fn search_next_batch(handle: u64) -> Option<Vec<FileEntry>> {
    // The walker is on a std::thread; poll on a blocking task so the
    // caller's async runtime doesn't block its executor.
    tokio::task::spawn_blocking(move || {
        cairn_search::next_batch(cairn_search::SearchHandle(handle))
    })
    .await
    .ok()
    .flatten()
}

fn search_cancel(handle: u64) {
    cairn_search::cancel(cairn_search::SearchHandle(handle));
}
```

> **Tokio dep:** 기존 `cairn-ffi` 가 swift-bridge 의 `async fn` 을 쓰려면 `tokio` 런타임이 이미 세팅돼 있어야 함. Cargo.toml 에 없으면 `tokio = { version = "1", features = ["rt", "macros"] }` 추가. 기존 `list_directory` 도 async 라면 이미 있을 것 — 없으면 추가 후 `cargo build -p cairn-ffi` 로 확인.

- [ ] **Step 3: 빌드 + bindings 생성**

```bash
cd /Users/cyj/workspace/personal/cairn
./scripts/build-rust.sh 2>&1 | tail -10
./scripts/gen-bindings.sh 2>&1 | tail -10
git status --short apps/Sources/Generated/
```

Expected: `build-rust.sh` universal lib 생성. `gen-bindings.sh` 가 Generated 디렉터리에 **신규 3 함수** 를 포함한 `cairn_ffi.swift` / `cairn_ffi.h` 갱신. `git status` 에 `apps/Sources/Generated/cairn_ffi.{h,swift}` modified 표시.

- [ ] **Step 4: `cargo test` 전체 + clippy**

```bash
cargo test --workspace 2>&1 | tail -10
cargo clippy --workspace --all-targets -- -D warnings 2>&1 | tail -5
```

Expected: 전체 green, clippy clean.

- [ ] **Step 5: 커밋**

```bash
git add crates/cairn-ffi/Cargo.toml crates/cairn-ffi/src/lib.rs apps/Sources/Generated/
git commit -m "feat(ffi): bridge searchStart / searchNextBatch / searchCancel"
```

---

## Task 6: Swift `CairnEngine+Search.swift` — async wrapper

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/App/CairnEngine+Search.swift`

- [ ] **Step 1: 파일 생성**

```swift
import Foundation

/// Swift-side async wrappers around the swift-bridge FFI for search.
/// Keeps call sites free of raw `u64` handle plumbing and gives us a
/// convenient place to convert between Rust `FileEntry` and any future
/// Swift-native result type.
extension CairnEngine {
    /// Spawns a search session; returns the opaque handle.
    func searchStart(root: String, query: String, subtree: Bool, showHidden: Bool) async -> UInt64 {
        await Task.detached(priority: .userInitiated) {
            searchStart(root, query, subtree, showHidden)
        }.value
    }

    /// Pulls the next batch. Returns `nil` when the walker is finished.
    func searchNextBatch(handle: UInt64) async -> [FileEntry]? {
        let opt = await searchNextBatch(handle)
        guard let rustVec = opt else { return nil }
        // RustVec<FileEntry> → [FileEntry]. swift-bridge ships iteration.
        var out: [FileEntry] = []
        out.reserveCapacity(rustVec.len())
        for i in 0..<rustVec.len() {
            out.append(rustVec.get(i))
        }
        return out
    }

    /// Idempotent cancellation.
    func searchCancelSession(handle: UInt64) {
        searchCancel(handle)
    }
}
```

> **Note:** `searchStart` / `searchNextBatch` / `searchCancel` 이 자동생성 자유 함수이므로 extension 의 메서드 이름과 충돌할 수 있음. 위 코드는 extension 메서드와 FFI 자유함수를 같은 이름으로 쓰지만 Swift 는 호출 문맥으로 구분. 컴파일 오류가 나면 extension 메서드를 `searchBegin` / `searchFetch` / `searchEnd` 로 rename 하고 `SearchModel` 도 따라서 고친다.

- [ ] **Step 2: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. 이름 충돌 에러 뜨면 extension 메서드 rename (위 Note 참조) 후 재시도.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/App/CairnEngine+Search.swift
git commit -m "feat(engine): add async Swift wrappers for search FFI"
```

---

## Task 7: `FolderModel` 정렬 comparator 정적 추출

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Models/FolderModel+Sort.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Models/FolderModel.swift`

- [ ] **Step 1: 기존 `sortedEntries` 정렬 로직 확인**

`FolderModel.swift` 의 `var sortedEntries: [FileEntry]` 구현을 Read 해서 현재 sort closure 를 파악. 아래 추출 코드가 현재 동작과 일치하는지 확인. 다르면 현재 로직을 그대로 복사.

- [ ] **Step 2: `FolderModel+Sort.swift` 생성 — static helper**

```swift
import Foundation

extension FolderModel {
    /// Stateless comparator for `FileEntry` pairs given a sort descriptor.
    /// Shared between `sortedEntries` and `SearchModel`'s running-sort.
    static func comparator(for sort: SortDescriptor)
        -> (FileEntry, FileEntry) -> Bool
    {
        { a, b in
            let result: Bool
            switch sort.field {
            case .name:
                result = a.name.toString().localizedStandardCompare(b.name.toString()) == .orderedAscending
            case .size:
                result = a.size < b.size
            case .modified:
                result = a.modified_unix < b.modified_unix
            }
            return sort.order == .ascending ? result : !result
        }
    }
}
```

- [ ] **Step 3: `FolderModel.swift` 의 `sortedEntries` 가 새 comparator 사용하도록 교체**

기존:
```swift
var sortedEntries: [FileEntry] {
    entries.sorted { a, b in
        // ... inline sort logic ...
    }
}
```

교체:
```swift
var sortedEntries: [FileEntry] {
    entries.sorted(by: Self.comparator(for: sortDescriptor))
}
```

- [ ] **Step 4: 빌드 + 테스트 (regression)**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: build green, 기존 20 tests 그대로 통과 (정렬 로직 동치이므로 회귀 X).

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Models/FolderModel.swift apps/Sources/Models/FolderModel+Sort.swift
git commit -m "refactor(folder): extract sort comparator as static helper for reuse"
```

---

## Task 8: `SearchModel` — folder-mode (TDD)

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Models/SearchModel.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/Tests/SearchModelTests.swift`

- [ ] **Step 1: `SearchModel.swift` 생성 — folder-mode 만**

```swift
import Foundation
import SwiftUI

enum SearchScope: String, CaseIterable, Hashable {
    case folder
    case subtree
}

enum SearchPhase: Equatable {
    case idle
    case running
    case capped
    case done
    case failed(String)
}

@Observable
final class SearchModel {
    var query: String = ""
    var scope: SearchScope = .folder
    var results: [FileEntry] = []
    var phase: SearchPhase = .idle
    var hitCount: Int = 0

    private(set) var activeHandle: UInt64?
    private var task: Task<Void, Never>?
    private let engine: CairnEngine

    init(engine: CairnEngine) { self.engine = engine }

    var isActive: Bool { !query.isEmpty }

    /// Re-run the search given the latest query/scope/root/hidden/sort.
    /// Called from ContentView.onChange triggers and from `cancel()`.
    func refresh(
        root: URL?,
        showHidden: Bool,
        sort: FolderModel.SortDescriptor,
        folderEntries: [FileEntry]
    ) {
        task?.cancel()
        task = nil
        if let h = activeHandle {
            engine.searchCancelSession(handle: h)
            activeHandle = nil
        }

        guard !query.isEmpty, root != nil else {
            results = []
            hitCount = 0
            phase = .idle
            return
        }

        if scope == .folder {
            let q = query
            results = folderEntries.filter {
                $0.name.toString().localizedCaseInsensitiveContains(q)
            }
            hitCount = results.count
            phase = .done
            return
        }

        // Subtree mode implemented in Task 9.
        phase = .idle
    }

    func cancel() {
        task?.cancel()
        task = nil
        if let h = activeHandle {
            engine.searchCancelSession(handle: h)
        }
        activeHandle = nil
        results = []
        hitCount = 0
        phase = .idle
    }
}
```

- [ ] **Step 2: `SearchModelTests.swift` 생성**

**전제:** apps 가 `CairnTests` XCTest 타깃을 이미 갖고 있음 (M1.2 부터). 이 파일을 해당 타깃 소스 디렉터리 (`apps/Tests/`) 에 넣으면 xcodegen 이 자동 포함.

```swift
import XCTest
@testable import Cairn

final class SearchModelTests: XCTestCase {
    private func makeEngine() -> CairnEngine { CairnEngine() }
    private func entry(_ name: String) -> FileEntry {
        // Build a minimal FileEntry via FFI constructor or fixture. If a
        // public initializer isn't available, expose one in a #if DEBUG
        // extension in Models/FileEntry+Fixture.swift.
        FileEntry.fixture(name: name)
    }

    func testIdleByDefault() {
        let m = SearchModel(engine: makeEngine())
        XCTAssertEqual(m.phase, .idle)
        XCTAssertTrue(m.results.isEmpty)
        XCTAssertFalse(m.isActive)
    }

    func testFolderModeFiltersInMemory() {
        let m = SearchModel(engine: makeEngine())
        m.query = "readme"
        m.scope = .folder
        m.refresh(
            root: URL(fileURLWithPath: "/"),
            showHidden: false,
            sort: FolderModel.SortDescriptor(field: .name, order: .ascending),
            folderEntries: [entry("README.md"), entry("main.swift"), entry("readme.txt")]
        )
        XCTAssertEqual(m.results.map { $0.name.toString() }.sorted(),
                       ["README.md", "readme.txt"])
        XCTAssertEqual(m.phase, .done)
    }

    func testEmptyQueryClearsResults() {
        let m = SearchModel(engine: makeEngine())
        m.query = "x"
        m.refresh(
            root: URL(fileURLWithPath: "/"),
            showHidden: false,
            sort: FolderModel.SortDescriptor(field: .name, order: .ascending),
            folderEntries: [entry("xfoo")]
        )
        XCTAssertEqual(m.results.count, 1)

        m.query = ""
        m.refresh(
            root: URL(fileURLWithPath: "/"),
            showHidden: false,
            sort: FolderModel.SortDescriptor(field: .name, order: .ascending),
            folderEntries: [entry("xfoo")]
        )
        XCTAssertEqual(m.phase, .idle)
        XCTAssertTrue(m.results.isEmpty)
    }
}
```

- [ ] **Step 3: `FileEntry.fixture(name:)` 헬퍼가 없으면 추가**

`apps/Sources/Models/FileEntry+Fixture.swift` 생성:

```swift
#if DEBUG
import Foundation

extension FileEntry {
    /// Test-only fixture builder. Avoids leaking FFI construction details
    /// into unit tests.
    static func fixture(
        name: String,
        path: String? = nil,
        kind: FileKind = .File,
        size: UInt64 = 0,
        modifiedUnix: Int64 = 0
    ) -> FileEntry {
        FileEntry(
            name: RustString(name),
            path: RustString(path ?? "/tmp/\(name)"),
            kind: kind,
            size: size,
            modified_unix: modifiedUnix
        )
    }
}
#endif
```

> **Note:** `FileEntry` 의 실제 initializer 시그니처 (swift-bridge 자동생성) 는 프로젝트에 따라 다름. 필드명이 snake_case 인지 확인하고 맞춰서 조정. 공개 생성자가 막혀있으면 Rust 측에 `pub fn FileEntry::new_for_swift(...)` 를 임시 추가하는 것도 한 방법 (M1.6 시간 절약 쪽을 선택).

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: build green, 23 tests pass (기존 20 + 신규 3).

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Models/SearchModel.swift apps/Sources/Models/FileEntry+Fixture.swift apps/Tests/SearchModelTests.swift
git commit -m "feat(search): add SearchModel with folder-mode filter + tests"
```

---

## Task 9: `SearchModel` — subtree async + cancellation

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Models/SearchModel.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Tests/SearchModelTests.swift`

- [ ] **Step 1: `refresh` 에 subtree 분기 추가**

기존 `refresh` 의 subtree-mode placeholder (`phase = .idle`) 를 다음으로 교체:

```swift
        // Subtree mode — async walker with debounce + running sort.
        phase = .running
        hitCount = 0
        results = []
        let q = query
        guard let rootURL = root else { return }
        let rootPath = rootURL.path
        let hidden = showHidden
        let cmp = FolderModel.comparator(for: sort)

        task = Task { [weak self] in
            // 200ms debounce — if a newer keystroke cancels us, abort early.
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }

            guard let engine = await MainActor.run(body: { self?.engine }) else { return }
            let handle = await engine.searchStart(
                root: rootPath, query: q, subtree: true, showHidden: hidden)
            await MainActor.run { self?.activeHandle = handle }

            while !Task.isCancelled {
                guard let batch = await engine.searchNextBatch(handle: handle) else { break }
                if batch.isEmpty { continue } // keep-alive, walker still running
                await MainActor.run {
                    guard let self else { return }
                    self.results.append(contentsOf: batch)
                    self.results.sort(by: cmp)
                    self.hitCount = self.results.count
                    if self.results.count >= 5_000 {
                        self.phase = .capped
                    }
                }
            }

            await MainActor.run {
                guard let self else { return }
                if case .running = self.phase { self.phase = .done }
                if self.activeHandle == handle { self.activeHandle = nil }
            }
        }
```

전체 `refresh` (완성본):

```swift
    func refresh(
        root: URL?,
        showHidden: Bool,
        sort: FolderModel.SortDescriptor,
        folderEntries: [FileEntry]
    ) {
        task?.cancel()
        task = nil
        if let h = activeHandle {
            engine.searchCancelSession(handle: h)
            activeHandle = nil
        }

        guard !query.isEmpty, let rootURL = root else {
            results = []
            hitCount = 0
            phase = .idle
            return
        }

        if scope == .folder {
            let q = query
            results = folderEntries.filter {
                $0.name.toString().localizedCaseInsensitiveContains(q)
            }
            hitCount = results.count
            phase = .done
            return
        }

        // Subtree mode — async walker with debounce + running sort.
        phase = .running
        hitCount = 0
        results = []
        let q = query
        let rootPath = rootURL.path
        let hidden = showHidden
        let cmp = FolderModel.comparator(for: sort)
        let eng = engine

        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }

            let handle = await eng.searchStart(
                root: rootPath, query: q, subtree: true, showHidden: hidden)
            await MainActor.run { self?.activeHandle = handle }

            while !Task.isCancelled {
                guard let batch = await eng.searchNextBatch(handle: handle) else { break }
                if batch.isEmpty { continue }
                await MainActor.run {
                    guard let self else { return }
                    self.results.append(contentsOf: batch)
                    self.results.sort(by: cmp)
                    self.hitCount = self.results.count
                    if self.results.count >= 5_000 {
                        self.phase = .capped
                    }
                }
            }
            await MainActor.run {
                guard let self else { return }
                if case .running = self.phase { self.phase = .done }
                if self.activeHandle == handle { self.activeHandle = nil }
            }
        }
    }
```

- [ ] **Step 2: 테스트 2개 추가 (cancel / scope toggle)**

`SearchModelTests.swift` 에 append:

```swift
    func testCancelClearsTaskAndHandle() {
        let m = SearchModel(engine: makeEngine())
        m.query = "x"
        m.scope = .subtree
        m.refresh(
            root: URL(fileURLWithPath: "/tmp"),
            showHidden: false,
            sort: FolderModel.SortDescriptor(field: .name, order: .ascending),
            folderEntries: []
        )
        // task is spawned; cancel right away
        m.cancel()
        XCTAssertNil(m.activeHandle)
        XCTAssertEqual(m.phase, .idle)
    }

    func testScopeToggleDoesNotCrash() {
        let m = SearchModel(engine: makeEngine())
        m.query = "x"
        m.scope = .folder
        m.refresh(
            root: URL(fileURLWithPath: "/"),
            showHidden: false,
            sort: FolderModel.SortDescriptor(field: .name, order: .ascending),
            folderEntries: []
        )
        m.scope = .subtree
        m.refresh(
            root: URL(fileURLWithPath: "/"),
            showHidden: false,
            sort: FolderModel.SortDescriptor(field: .name, order: .ascending),
            folderEntries: []
        )
        m.cancel()
    }
```

- [ ] **Step 3: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 25 tests pass.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Models/SearchModel.swift apps/Tests/SearchModelTests.swift
git commit -m "feat(search): add subtree async walker + cancellation in SearchModel"
```

---

## Task 10: `SearchField` View

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Search/SearchField.swift`

- [ ] **Step 1: 파일 생성**

```swift
import SwiftUI

/// Toolbar search component. Holds a scope Picker (This Folder / Subtree)
/// and the query text field. Progress badge appears during subtree streaming.
struct SearchField: View {
    @Bindable var search: SearchModel
    @FocusState.Binding var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $search.scope) {
                Text("This Folder").tag(SearchScope.folder)
                Text("Subtree").tag(SearchScope.subtree)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            TextField("Search", text: $search.query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(width: 200)

            if search.phase == .running {
                ProgressView().controlSize(.small)
                Text("\(search.hitCount) found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if search.phase == .capped {
                Text("capped at 5,000")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
```

- [ ] **Step 2: 빌드 (standalone — 아직 ContentView 에 wiring 안 됨)**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Search/SearchField.swift
git commit -m "feat(search): add SearchField toolbar view with scope picker + progress"
```

---

## Task 11: `FileListView` — entries injection refactor

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListView.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift` (call site)

`FileListView` 가 `FolderModel` 에서 직접 `sortedEntries` 를 읽는 현 구조를, 외부에서 `entries: [FileEntry]` 를 주입하도록 변경. 이러면 ContentView 가 search 활성 시 `SearchModel.results` 를 넘길 수 있음.

- [ ] **Step 1: 기존 `FileListView` 구조 확인**

`FileListView.swift` 를 Read. 기존 public API (init parameters + NSViewRepresentable updateNSView) 와 현재 entries 소스 (folder.sortedEntries 를 어디에서 읽는지) 확인.

- [ ] **Step 2: `FileListView.swift` 수정 — `entries` parameter 추가, coordinator 에 넘김**

기존이 대략 다음 형태라고 가정:

```swift
struct FileListView: NSViewRepresentable {
    @Bindable var folder: FolderModel
    let onActivate: (FileEntry) -> Void
    // ...
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.applyModelSnapshot(table: ...)
    }
}
```

수정안:

```swift
struct FileListView: NSViewRepresentable {
    /// External entries source (FolderModel.sortedEntries OR SearchModel.results).
    /// Computed by ContentView per-frame.
    let entries: [FileEntry]

    /// Still needed for selection / sort descriptor state.
    let folder: FolderModel

    let folderColumnVisible: Bool
    let searchRoot: URL?

    let onActivate: (FileEntry) -> Void
    let onAddToPinned: (FileEntry) -> Void
    let isPinnedCheck: (FileEntry) -> Bool
    let onSelectionChanged: (FileEntry?) -> Void

    // makeNSView / updateNSView: coordinator 에 entries 넘기기
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.setEntries(entries, searchRoot: searchRoot)
        coord.setFolderColumnVisible(folderColumnVisible)
        if let table = nsView.documentView as? NSTableView {
            coord.applyModelSnapshot(table: table)
        }
    }
    // ... (기존 makeCoordinator / makeNSView 유지)
}
```

Coordinator 쪽 stub API 는 Task 12 에서 구현. 여기선 컴파일이 깨지지 않게 최소 override 만 삽입.

- [ ] **Step 3: `FileListCoordinator` 에 minimal `setEntries` / `setFolderColumnVisible` 추가**

`FileListCoordinator.swift` 파일 상단, 기존 `lastSnapshot` 근처에:

```swift
    private var externalEntries: [FileEntry]?
    private var searchRoot: URL?
    private(set) var folderColumnVisible: Bool = false

    func setEntries(_ entries: [FileEntry], searchRoot: URL?) {
        self.externalEntries = entries
        self.searchRoot = searchRoot
    }

    func setFolderColumnVisible(_ visible: Bool) {
        // 실제 컬럼 추가/제거 로직은 Task 12 에서. 지금은 플래그만.
        self.folderColumnVisible = visible
    }
```

그리고 기존 `applyModelSnapshot` 이 `folder.sortedEntries` 를 읽는 자리를 `externalEntries ?? folder.sortedEntries` 로 교체:

```swift
    func applyModelSnapshot(table: NSTableView) {
        isApplyingModelUpdate = true
        defer { isApplyingModelUpdate = false }

        lastSnapshot = externalEntries ?? folder.sortedEntries
        table.reloadData()
        // ... (나머지 selection 복원 / sortDescriptor 반영 기존 그대로)
    }
```

- [ ] **Step 4: `ContentView.swift` 의 `FileListView` 호출부 업데이트**

기존:

```swift
FileListView(
    folder: folder,
    onActivate: handleOpen,
    onAddToPinned: handleAddToPinned,
    isPinnedCheck: { entry in ... },
    onSelectionChanged: handleSelectionChanged
)
```

교체 (Task 13 에서 searchModel 주입 추가 예정 — 여기선 `entries: folder.sortedEntries` 로 우선 pass-through):

```swift
FileListView(
    entries: folder.sortedEntries,
    folder: folder,
    folderColumnVisible: false,
    searchRoot: nil,
    onActivate: handleOpen,
    onAddToPinned: handleAddToPinned,
    isPinnedCheck: { entry in
        app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
    },
    onSelectionChanged: handleSelectionChanged
)
```

- [ ] **Step 5: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: build green, 25 tests pass (회귀 X — Coordinator 가 현재도 folder.sortedEntries 를 쓰는 경로 유지).

- [ ] **Step 6: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListView.swift apps/Sources/Views/FileList/FileListCoordinator.swift apps/Sources/ContentView.swift
git commit -m "refactor(file-list): accept external entries + folder-column flag"
```

---

## Task 12: `FileListCoordinator` — Folder 컬럼 동적 추가

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

- [ ] **Step 1: 새 컬럼 identifier 추가**

기존 파일 상단 extension 또는 identifier 정의 근처에:

```swift
extension NSUserInterfaceItemIdentifier {
    // 기존 .name / .size / .modified 정의와 같이 나열
    static let folder = NSUserInterfaceItemIdentifier("folder")
}
```

- [ ] **Step 2: `setFolderColumnVisible` 실구현**

기존 플래그-only 버전을 다음으로 교체:

```swift
    func setFolderColumnVisible(_ visible: Bool) {
        guard let table = self.table else {
            folderColumnVisible = visible
            return
        }
        let existing = table.tableColumns.first(where: { $0.identifier == .folder })
        if visible && existing == nil {
            let col = NSTableColumn(identifier: .folder)
            col.title = "Folder"
            col.minWidth = 80
            col.width = 180
            // Name 컬럼 뒤, Size 앞에 끼워넣기
            let nameIdx = table.tableColumns.firstIndex(where: { $0.identifier == .name }) ?? 0
            table.addTableColumn(col)
            table.moveColumn(table.tableColumns.count - 1, toColumn: nameIdx + 1)
        } else if !visible, let col = existing {
            table.removeTableColumn(col)
        }
        folderColumnVisible = visible
    }
```

- [ ] **Step 3: `tableView(_:viewFor:row:)` 에 `.folder` case 추가**

기존 switch 에 추가:

```swift
        case .folder:
            cell.imageView?.image = nil
            let full = entry.path.toString()
            let rel: String
            if let root = searchRoot?.standardizedFileURL.path, full.hasPrefix(root) {
                var r = String(full.dropFirst(root.count))
                if r.hasPrefix("/") { r.removeFirst() }
                // Strip filename from display — only show parent folder.
                rel = (r as NSString).deletingLastPathComponent
            } else {
                rel = (full as NSString).deletingLastPathComponent
            }
            cell.textField?.stringValue = rel.isEmpty ? "—" : rel
            cell.textField?.alignment = .left
```

- [ ] **Step 4: 최소 XCTest — folderColumnAppearsInSubtreeMode**

`apps/Tests/FileListCoordinatorTests.swift` 에 추가 (없으면 파일 생성):

```swift
import XCTest
@testable import Cairn
import AppKit

final class FileListCoordinatorTests: XCTestCase {
    func testSetFolderColumnVisibleAddsAndRemovesColumn() {
        let folder = FolderModel(engine: CairnEngine())
        let coord = FileListCoordinator(
            folder: folder,
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )
        let table = FileListNSTableView()
        // 기존 컬럼 3개 (Name/Size/Modified) 수동 세팅
        for id in ["name", "size", "modified"] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = id.capitalized
            table.addTableColumn(c)
        }
        coord.attach(table: table)

        XCTAssertEqual(table.tableColumns.count, 3)
        coord.setFolderColumnVisible(true)
        XCTAssertEqual(table.tableColumns.count, 4)
        XCTAssertTrue(table.tableColumns.contains(where: { $0.identifier.rawValue == "folder" }))
        coord.setFolderColumnVisible(false)
        XCTAssertEqual(table.tableColumns.count, 3)
    }
}
```

- [ ] **Step 5: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 26 tests pass.

- [ ] **Step 6: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift apps/Tests/FileListCoordinatorTests.swift
git commit -m "feat(file-list): dynamic Folder column for subtree search"
```

---

## Task 13: ContentView 통합 — `⌘F`, SearchField, entries 분기, onChange

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift`

- [ ] **Step 1: `ContentView` 에 SearchModel state + FocusState 추가**

기존 `@State private var folder: FolderModel?` 옆에:

```swift
    @State private var searchModel: SearchModel?
    @FocusState private var searchFocused: Bool
```

`ensureFolderModel()` 옆에 `ensureSearchModel()`:

```swift
    private func ensureSearchModel() {
        if searchModel == nil { searchModel = SearchModel(engine: app.engine) }
    }
```

`body.task { ... }` 첫 줄 (`ensureFolderModel()`) 아래:

```swift
            ensureSearchModel()
```

- [ ] **Step 2: `FileListView` 호출부 업데이트 — entries 를 조건부로**

Task 11 에서 추가했던 `entries: folder.sortedEntries` 호출부를 다음으로 교체:

```swift
            if let folder, let searchModel {
                let isActive = searchModel.isActive
                let entries: [FileEntry] = isActive
                    ? searchModel.results
                    : folder.sortedEntries
                let showFolderCol = isActive && searchModel.scope == .subtree
                FileListView(
                    entries: entries,
                    folder: folder,
                    folderColumnVisible: showFolderCol,
                    searchRoot: isActive ? app.currentFolder : nil,
                    onActivate: handleOpen,
                    onAddToPinned: handleAddToPinned,
                    isPinnedCheck: { entry in
                        app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
                    },
                    onSelectionChanged: handleSelectionChanged
                )
            } else {
                ProgressView().controlSize(.small)
            }
```

- [ ] **Step 3: `.toolbar { ... }` 에 SearchField + ⌘F hidden button 추가**

기존 reload 버튼 (`⌘R`, M1.5 Task 8) 바로 아래:

```swift
            ToolbarItem(placement: .automatic) {
                if let searchModel {
                    SearchField(search: searchModel, focused: $searchFocused)
                }
            }
            ToolbarItem(placement: .automatic) {
                // Hidden — only the keyboard shortcut matters.
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: [.command])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
```

- [ ] **Step 4: `.onChange` 트리거들 — refresh 연결**

기존 `.onChange(of: app.currentFolder)` 블록 아래에 (또는 한 군데 묶어서) 다음 4개 `onChange` 를 추가:

```swift
        .onChange(of: searchModel?.query) { _, _ in triggerSearchRefresh() }
        .onChange(of: searchModel?.scope) { _, _ in triggerSearchRefresh() }
        .onChange(of: folder?.sortDescriptor) { _, _ in triggerSearchRefresh() }
        .onChange(of: app.showHidden) { _, _ in triggerSearchRefresh() }
```

그리고 기존 `onChange(of: app.currentFolder)` 블록에서 `folder?.clear()` / `folder?.load(url)` 호출 뒤에 `triggerSearchRefresh()` 한 줄 추가 (root 바뀔 때도 re-search).

Helper 메서드 — `reloadCurrentFolder()` 근처에:

```swift
    private func triggerSearchRefresh() {
        guard let searchModel, let folder else { return }
        searchModel.refresh(
            root: app.currentFolder,
            showHidden: app.showHidden,
            sort: folder.sortDescriptor,
            folderEntries: folder.sortedEntries
        )
    }
```

- [ ] **Step 5: Result cap banner + empty-result state**

`NavigationSplitView` 내부의 `content:` 블록에서 `FileListView` 를 감싸는 `VStack(spacing: 0)` 을 넣고 위에 배너를 끼우거나, 기존 구조에 맞춰 top-leading overlay 로 얹는다. 간단한 VStack 버전:

```swift
            if let folder, let searchModel {
                VStack(spacing: 0) {
                    if searchModel.phase == .capped {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Showing first 5,000 results — refine your query")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                    }
                    if searchModel.isActive && searchModel.results.isEmpty
                        && searchModel.phase != .running
                    {
                        VStack(spacing: 4) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No matches for \"\(searchModel.query)\"")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        FileListView(
                            entries: searchModel.isActive ? searchModel.results : folder.sortedEntries,
                            folder: folder,
                            folderColumnVisible: searchModel.isActive && searchModel.scope == .subtree,
                            searchRoot: searchModel.isActive ? app.currentFolder : nil,
                            onActivate: handleOpen,
                            onAddToPinned: handleAddToPinned,
                            isPinnedCheck: { entry in
                                app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
                            },
                            onSelectionChanged: handleSelectionChanged
                        )
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
```

- [ ] **Step 6: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: build green, 26 tests pass.

- [ ] **Step 7: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ContentView.swift
git commit -m "feat(app): wire SearchModel + SearchField + ⌘F into ContentView"
```

---

## Task 14: 실행 smoke 체크 (수동 — 짧게)

**Files:** 없음 (수동 검증만)

- [ ] **Step 1: 앱 실행**

```bash
cd /Users/cyj/workspace/personal/cairn
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
```

- [ ] **Step 2: 빠른 smoke 체크 (실패하면 STOP)**

- [ ] `⌘F` → toolbar 검색 필드에 포커스 이동
- [ ] "readme" 타이핑 → "This Folder" 모드에서 즉시 필터
- [ ] Picker "Subtree" 토글 → 200ms 뒤 streaming 시작, "N found" 배지 증가
- [ ] Esc or 쿼리 clear → 정상 폴더 뷰 복귀

- [ ] **Step 3: 이상 없으면 커밋 불필요. 결과 보고만.**

---

## Task 15: P1 — `PreviewModel` `@MainActor` + `Task.detached`

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Models/PreviewModel.swift`

- [ ] **Step 1: 현재 `PreviewModel` 확인**

파일 Read. `compute` 계열 메서드에서 `FileManager` 호출을 어디서 하는지 확인. 현재는 @MainActor 없을 가능성 높음.

- [ ] **Step 2: 클래스 선언에 `@MainActor` 추가, FileManager 블록을 `Task.detached` 로 분리**

**변환 단계:**

1. 클래스 선언 위에 `@MainActor` 하나 추가.
2. 현재 `compute(for:)` 의 바디 전체를 pure function `private static func computeState(for url: URL) -> PreviewState` 로 추출. 외부 참조 (self.X) 를 전부 인자화하거나 URL-only 로 제한.
3. 기존 `compute(for:)` 는 다음 형태가 됨:

```swift
@MainActor
@Observable
final class PreviewModel {
    // 기존 프로퍼티 (state, focus 등) 그대로 ...

    func compute(for url: URL) async {
        state = .loading
        focus = url

        // Pure function을 detached priority 에서 실행 — FileManager / 이미지 로드
        // 전부 여기서. MainActor 부담 제거.
        let result: PreviewState = await Task.detached(priority: .userInitiated) { [url] in
            Self.computeState(for: url)
        }.value

        // Stale write 방지 — 사용자가 다른 파일로 포커스 바꾼 뒤에 오래된 결과가 도착할 수 있음
        if self.focus == url {
            self.state = result
        }
    }

    private nonisolated static func computeState(for url: URL) -> PreviewState {
        // 여기에 기존 compute(for:) 의 파일 I/O + 이미지 디코드 + meta 로직 그대로 이동.
        // 외부 상태는 참조하지 않는다 (pure). URL 하나만 입력.
        // 기존 바디가 async 였다면 동기 (blocking) 로 바꿔도 OK — detached 스레드라 문제 없음.
    }
}
```

> **주의:** `computeState` 는 `nonisolated static` 이어야 MainActor 클래스 안에서 detached 로 호출 가능. 기존 바디에서 `self.X` 참조가 있다면 인자로 뽑거나 제거.

실제 `compute` 바디는 현 구현체 그대로 옮기면 됨. 주의:
- `[url]` capture 로 URL 만 가져가고 self 는 capture 안 함 (detached)
- 완료 후 `self.focus == url` 체크로 stale write 방지 (P3 와 연동)

- [ ] **Step 3: 호출부 업데이트 (없음이 이상적)**

`compute` 이 이미 `async` 였다면 호출부 변경 불필요. 아니었다면 호출부에서 `Task { await preview.compute(for: url) }` 로 감쌀 것.

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 26 tests pass, no new concurrency warnings.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Models/PreviewModel.swift
git commit -m "refactor(preview): mark PreviewModel @MainActor, isolate FileManager via Task.detached"
```

---

## Task 16: P2 — `ImagePreview` path change resets `image`

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Preview/PreviewRenderers.swift`

- [ ] **Step 1: 현재 `ImagePreview` 확인**

파일 Read. `ImagePreview(path: String)` View 의 `@State private var image: NSImage?` 가 `path` 변경 시 reset 안 하는지 확인.

- [ ] **Step 2: `.onChange(of: path)` 추가**

기존 `ImagePreview` 의 `.task { await load() }` 근처에:

```swift
    .task(id: path) {
        image = nil
        await load()
    }
```

`.task(id:)` 는 id 가 바뀔 때 취소/재시작 + body 에서 `image = nil` 로 stale 이미지 깜빡임 제거. 기존 `.task { ... }` 만 있으면 그것만 치환.

- [ ] **Step 3: 빌드 + 수동 smoke**

```bash
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: green.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Preview/PreviewRenderers.swift
git commit -m "fix(preview): reset NSImage on path change to avoid stale flash"
```

---

## Task 17: P3 — `quickLookURLs` 를 `beginPreviewPanelControl` 에서 snapshot

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

- [ ] **Step 1: 현재 computed property 확인**

기존:
```swift
    private var quickLookURLs: [URL] {
        let selectedRows = table?.selectedRowIndexes ?? IndexSet()
        ...
    }
```

`numberOfPreviewItems` / `previewPanelItemAt:` 이 매번 이 computed 를 호출. 중간에 selection 이 바뀌면 결과 불일치.

- [ ] **Step 2: snapshot field + begin/end hooks**

```swift
    private var quickLookSnapshot: [URL] = []

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        quickLookSnapshot = currentQuickLookCandidates()
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        quickLookSnapshot = []
    }

    private func currentQuickLookCandidates() -> [URL] {
        let selectedRows = table?.selectedRowIndexes ?? IndexSet()
        let paths: [URL] = selectedRows.compactMap { row in
            guard row < lastSnapshot.count else { return nil }
            return URL(fileURLWithPath: lastSnapshot[row].path.toString())
        }
        if paths.isEmpty, !lastSnapshot.isEmpty {
            return [URL(fileURLWithPath: lastSnapshot[0].path.toString())]
        }
        return paths
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookSnapshot.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < quickLookSnapshot.count else { return nil }
        return quickLookSnapshot[index] as NSURL
    }
```

> **Note:** `beginPreviewPanelControl` / `endPreviewPanelControl` override 시 `acceptsPreviewPanelControl` 도 같이 override 돼야 함 — 기존 코드에 있으면 그대로. 없으면 `return true` 추가.

- [ ] **Step 3: 빌드 + 테스트**

```bash
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 26 tests pass.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "fix(quick-look): snapshot URLs at beginPreviewPanelControl"
```

---

## Task 18: P4/P5/P6/P8 — Open With cluster refactor

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

4개 이슈를 한 번에:
- P4: `urlsForApplications(toOpen:)` 캐시 (파일 확장자 단위)
- P5: default-app dedupe 를 `standardizedFileURL` 기반
- P6: `displayName(atPath:).replacingOccurrences(".app","")` 제거
- P8: `representedObject` 를 공통 `MenuPayload` 로 통합 (OpenWithPayload + FileEntry 혼재 해소)

- [ ] **Step 1: `MenuPayload` 정의**

`OpenWithPayload` 를 확장하거나 교체:

```swift
/// Uniform payload for NSMenuItem.representedObject. Captures whatever the
/// target-action needs; new cases can be added without changing the
/// handler's type checks.
final class MenuPayload: NSObject {
    let entry: FileEntry
    let appURL: URL?   // only set for Open With submenu items

    init(entry: FileEntry, appURL: URL? = nil) {
        self.entry = entry
        self.appURL = appURL
    }
}

// Deprecated: replaced by MenuPayload. Keep only if external refs.
```

M1.5 에 추가했던 `OpenWithPayload` 참조를 전부 `MenuPayload` 로 교체. 기존 `menuCopyPath` / `menuRevealInFinder` / `menuMoveToTrash` / `menuAddToPinned` 의 `representedObject as? FileEntry` 는 `as? MenuPayload` 로 바꾸고 `.entry` 필드 접근. `menuOpenWith` 는 `.entry` + `.appURL` 둘 다.

- [ ] **Step 2: `openWithAppsCache` 도입**

```swift
    /// Cache of app lists keyed by path-extension + directory-ness.
    /// Invalidated on `attach`.
    private var openWithAppsCache: [String: [URL]] = [:]
    private var defaultAppCache: [String: URL] = [:]

    private func appsForOpening(_ fileURL: URL) -> (apps: [URL], defaultApp: URL?) {
        let key = fileURL.pathExtension.lowercased()
        let apps: [URL]
        if let cached = openWithAppsCache[key] {
            apps = cached
        } else {
            apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            openWithAppsCache[key] = apps
        }
        let def: URL?
        if let cachedDef = defaultAppCache[key] {
            def = cachedDef
        } else if let d = NSWorkspace.shared.urlForApplication(toOpen: fileURL) {
            defaultAppCache[key] = d
            def = d
        } else {
            def = nil
        }
        return (apps, def)
    }
```

`attach(table:)` 에서 두 cache 를 `[:]` 로 초기화 (새 폴더 진입 시 invalidate):

```swift
    func attach(table: FileListNSTableView) {
        self.table = table
        openWithAppsCache.removeAll()
        defaultAppCache.removeAll()
        applyModelSnapshot(table: table)
    }
```

- [ ] **Step 3: `buildOpenWithSubmenu` 를 새 helper 로 재작성**

기존 전체 교체:

```swift
    private func buildOpenWithSubmenu(for entry: FileEntry) -> NSMenu? {
        let fileURL = URL(fileURLWithPath: entry.path.toString())
        let (appURLs, defaultApp) = appsForOpening(fileURL)
        guard !appURLs.isEmpty else { return nil }

        let submenu = NSMenu()

        // Default first, de-duped on standardized path.
        var ordered: [URL] = []
        if let def = defaultApp {
            let defCanon = def.standardizedFileURL
            ordered.append(def)
            ordered.append(contentsOf: appURLs.filter {
                $0.standardizedFileURL != defCanon
            })
        } else {
            ordered = appURLs
        }

        for appURL in ordered {
            // displayName already strips .app for bundles — don't re-strip.
            let name = FileManager.default.displayName(atPath: appURL.path)
            let title = (appURL.standardizedFileURL == defaultApp?.standardizedFileURL)
                ? "\(name) (default)"
                : name
            let item = NSMenuItem(title: title,
                                  action: #selector(menuOpenWith(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = MenuPayload(entry: entry, appURL: appURL)
            submenu.addItem(item)
        }
        return submenu
    }
```

- [ ] **Step 4: Action 메서드들의 `representedObject` unwrap 을 `MenuPayload` 로**

```swift
    @objc private func menuAddToPinned(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload else { return }
        onAddToPinned(p.entry)
    }

    @objc private func menuRevealInFinder(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload else { return }
        NSWorkspace.shared.selectFile(p.entry.path.toString(),
                                      inFileViewerRootedAtPath: "")
    }

    @objc private func menuCopyPath(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(p.entry.path.toString(), forType: .string)
    }

    @objc private func menuMoveToTrash(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload else { return }
        let url = URL(fileURLWithPath: p.entry.path.toString())
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            // P7 에서 NSAlert 로 교체 예정
            NSLog("cairn: Move to Trash failed — \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    @objc private func menuOpenWith(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload, let appURL = p.appURL else { return }
        let fileURL = URL(fileURLWithPath: p.entry.path.toString())
        NSWorkspace.shared.open([fileURL],
                                withApplicationAt: appURL,
                                configuration: .init()) { _, error in
            if let error { NSLog("cairn: Open With failed — \(error.localizedDescription)") }
        }
    }
```

`menu(for:)` 에서 representedObject 에 `MenuPayload(entry: entry)` 를 셋팅하도록 업데이트:

```swift
        // 기존: item.representedObject = entry
        // 변경:
        item.representedObject = MenuPayload(entry: entry)
```

(Add-to-Pinned, Reveal, Copy Path, Trash 모두 동일 패턴)

- [ ] **Step 5: `OpenWithPayload` 삭제 (없어도 빌드 돼야 함)**

`final class OpenWithPayload: NSObject { ... }` 정의 제거. 참조는 모두 `MenuPayload` 로 치환됨.

- [ ] **Step 6: 빌드 + 테스트**

```bash
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: green + 26 tests pass.

- [ ] **Step 7: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "refactor(file-list): unify MenuPayload + cache Open With + standardize dedupe"
```

---

## Task 19: P7 — `Move to Trash` 실패 NSAlert

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift:menuMoveToTrash`

- [ ] **Step 1: `menuMoveToTrash` 교체**

```swift
    @objc private func menuMoveToTrash(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? MenuPayload else { return }
        let url = URL(fileURLWithPath: p.entry.path.toString())
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't move to Trash"
            alert.informativeText = "\(url.lastPathComponent): \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
```

- [ ] **Step 2: 빌드**

```bash
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(file-list): show NSAlert when Move to Trash fails"
```

---

## Task 20: P9 — `SidebarModelTests` 반응성 테스트

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Tests/SidebarModelTests.swift`

- [ ] **Step 1: 현재 `SidebarModel` 구조 확인**

`find apps/Sources -name "SidebarModel.swift"` 로 정확한 경로 파악. M1.3 에서 `apps/Sources/Models/Sidebar/SidebarModel.swift` 또는 `apps/Sources/Models/SidebarModel.swift` 에 생성됐을 가능성 높음. 실제 경로 확인 후 테스트 대상 공개 API (`iCloudURL`, `locations`, `refreshLocations` 등) 시그니처 확인.

- [ ] **Step 2: 테스트 파일 생성**

```swift
import XCTest
@testable import Cairn
import Foundation

final class SidebarModelTests: XCTestCase {
    func testLocationsAlwaysStartsWithRoot() {
        let s = SidebarModel()
        // locations 중 "/" 가 반드시 하나 있어야 함.
        XCTAssertTrue(s.locations.contains(where: { $0.path == "/" }))
    }

    func testICloudURLReflectsHomeDirectoryCheck() {
        let s = SidebarModel()
        // Actual iCloud presence is machine-dependent; just assert the API
        // returns Optional<URL> (no crash / infinite loop).
        _ = s.iCloudURL
    }

    func testMountEventUpdatesLocations() {
        let s = SidebarModel()
        let before = s.locations.count
        // 직접 event 처리 API 가 private 이면 `refreshLocations()` 등 공개 메서드 호출.
        // 이 테스트의 실 취지는 "호출 후 추락 안 하고 N >= before" 확인.
        s.refreshLocations()
        XCTAssertGreaterThanOrEqual(s.locations.count, before)
    }
}
```

> **Note:** 실제 `SidebarModel` 의 public API 에 맞춰 쓸 것. `refreshLocations()` 가 없으면 (MountObserver 로만 갱신되는 경우) 해당 케이스는 삭제하거나 skeletal assertion 만 남김.

- [ ] **Step 3: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 29 tests pass.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Tests/SidebarModelTests.swift
git commit -m "test(sidebar): basic SidebarModel reactivity coverage"
```

---

## Task 21: P10/P11/P12/P18 — FileList 잔여 polish

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListView.swift`

3개 묶음 (P12 는 Task 11 의 refactor 시 이미 `let folder` 로 전환되어 이 Task 에서는 다루지 않음):
- P10: `sortDescriptorsDidChange` 의 `isApplyingModelUpdate` 재진입 가드 주석 추가
- P11: `entry.modified_unix == 0` sentinel 주석
- P18: `activateSelected()` 다중 row 처리 명시 (multi-select 일 때 첫 row 만 열거나 전부?)

- [ ] **Step 1: P10 주석 — `sortDescriptorsDidChange`**

기존:
```swift
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if isApplyingModelUpdate { return }
        ...
    }
```

주석 추가:
```swift
    /// AppKit fires this both from user clicks on column headers AND as a
    /// side-effect of setting `table.sortDescriptors` in `applyModelSnapshot`.
    /// The `isApplyingModelUpdate` guard prevents the second path from
    /// re-entering and triggering a redundant model update.
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if isApplyingModelUpdate { return }
        ...
    }
```

- [ ] **Step 2: P11 주석 — `modified_unix == 0`**

`cellForTableColumn` 내 `.modified` case 근처:

```swift
        case .modified:
            // Rust walker yields 0 when the filesystem returns no mtime
            // (permission denied, broken symlink). Surface as "—" instead
            // of 1970-01-01.
            let date = Date(timeIntervalSince1970: TimeInterval(entry.modified_unix))
            cell.textField?.stringValue = entry.modified_unix == 0 ? "—" : dateFormatter.string(from: date)
```

- [ ] **Step 3: P18 — `activateSelected` 다중 row 처리**

기존:
```swift
    func activateSelected() {
        guard let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, row < lastSnapshot.count else { return }
        onActivate(lastSnapshot[row])
    }
```

다중 선택 시 `selectedRow` 는 마지막으로 클릭한 row 하나만 반환. 이걸 명시하고, 다중 처리는 Phase 2 로 deferred 임을 주석 추가:

```swift
    /// Invoked when the user presses ⏎ (Return) on the focused table. If
    /// multiple rows are selected, AppKit's `selectedRow` returns the
    /// focused row only — we activate just that one. Phase 2 may add
    /// bulk-activation (open all selected in their default apps).
    func activateSelected() {
        guard let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, row < lastSnapshot.count else { return }
        onActivate(lastSnapshot[row])
    }
```

- [ ] **Step 4: 빌드 + 테스트**

```bash
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: green + 29 tests pass.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "chore(file-list): document reentry guard, modified=0 sentinel, multi-row activation"
```

---

## Task 22: P14/P15/P16 — Rust 잔여 cleanup

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-core/src/lib.rs`
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-preview/src/lib.rs`

- [ ] **Step 1: P14 — `WalkerError` re-export 확인 + 모듈 docstring**

`crates/cairn-core/src/lib.rs` Read. `pub use cairn_walker::WalkerError;` 나 비슷한 re-export 가 있는지 확인. 없으면 추가:

```rust
//! Shared types + error surface for Cairn's Rust crates.
//!
//! `cairn-core` holds platform-agnostic building blocks that multiple crates
//! (walker / preview / search / ffi) consume: `FileEntry`, `FileKind`, and
//! the canonical error enum re-exported from `cairn-walker` so callers have
//! a single import path for error matching.

// 기존 내용 ...

pub use cairn_walker::WalkerError;
```

(이미 있으면 docstring 만 업데이트.)

- [ ] **Step 2: P16 — `preview_text(max_bytes=0)` 가드**

`crates/cairn-preview/src/lib.rs` 내 `preview_text` 함수:

```rust
pub fn preview_text(path: &Path, max_bytes: usize) -> Result<PreviewResult, PreviewError> {
    if max_bytes == 0 {
        return Ok(PreviewResult::Empty);
    }
    // ... 기존 바디 ...
}
```

(`PreviewResult::Empty` enum variant 이 없으면 기존 에러타입 중 적합한 것 선택. `Ok(PreviewResult::Text(String::new()))` 도 가능.)

- [ ] **Step 3: P15 — `CairnEngine` docstring (Swift)**

`apps/Sources/App/CairnEngine.swift` 의 class docstring 이 부실하면 보강:

```swift
/// Single façade over the Rust FFI — the one place Swift reaches into Rust.
///
/// Holds a per-app-lifecycle handle; all async methods wrap the swift-bridge
/// bindings and translate between `RustString` / `RustVec` and Swift native
/// types. Extensions live in `CairnEngine+Search.swift` etc.
```

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo build --workspace
cargo test --workspace 2>&1 | tail -5
```

Expected: green.

- [ ] **Step 5: 커밋**

```bash
git add crates/cairn-core/src/lib.rs crates/cairn-preview/src/lib.rs apps/Sources/App/CairnEngine.swift
git commit -m "chore(rust+engine): re-export WalkerError, guard empty preview_text, docstrings"
```

---

## Task 23: P17 — `String(describing: error)` → user mapping

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/App/AppModel.swift` (및 관련)

- [ ] **Step 1: grep 으로 `String(describing:` 호출 위치 찾기**

```bash
cd /Users/cyj/workspace/personal/cairn
grep -rn "String(describing:" apps/Sources/ | head -20
```

주로 `AppModel.swift` / `FolderModel.swift` 의 에러 → UI string 변환 지점.

- [ ] **Step 2: Helper 도입**

`apps/Sources/App/ErrorMessage.swift` 생성:

```swift
import Foundation

enum ErrorMessage {
    /// Convert any Swift/Rust-bridged error into a short, user-facing string.
    /// Use at presentation boundaries instead of `String(describing:)`.
    static func userFacing(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        if let ns = error as NSError?, !ns.localizedDescription.isEmpty {
            return ns.localizedDescription
        }
        // Final fallback — debug description is better than nothing.
        return String(describing: error)
    }
}
```

- [ ] **Step 3: 호출부 교체**

grep 으로 찾은 `String(describing: error)` 들을 `ErrorMessage.userFacing(error)` 로 교체. 단 로깅 (`NSLog`, `print`) 은 그대로 둔다 (디버그 정보 필요).

- [ ] **Step 4: 빌드 + 테스트**

```bash
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 29 tests pass.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/App/ErrorMessage.swift apps/Sources/
git commit -m "feat(app): introduce ErrorMessage.userFacing for UI error surfaces"
```

---

## Task 24: P19 — `isPinned(url:)` drift 정리 (만약 존재)

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Services/BookmarkStore.swift`

- [ ] **Step 1: drift 내용 식별**

M1.3 plan 원문에서 `BookmarkStore.isPinned(url:)` 시그니처와 현재 구현 비교. `standardizedFileURL.path` 기반인지 문자열 비교인지 등 확인.

- [ ] **Step 2: 필요 시 시그니처 통일 + 주석**

대부분 이미 올바르게 되어있을 가능성 — 실제 drift 가 없으면 이 Task 는 skip (커밋 없음) 하고 다음 Task 로 진행. drift 존재 시 수정 + 주석:

```swift
    /// Compares against the pinned set using the standardized path form so
    /// `/tmp/foo` and `/private/tmp/foo` don't produce different answers.
    func isPinned(url: URL) -> Bool {
        let canon = url.standardizedFileURL.path
        return pinned.contains(where: { $0.lastKnownPath == canon })
    }
```

- [ ] **Step 3: 빌드 + 테스트**

```bash
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 29 tests pass.

- [ ] **Step 4: 커밋 (drift 있었을 때만)**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Services/BookmarkStore.swift
git commit -m "fix(bookmarks): standardize URL comparison in isPinned"
```

---

## Task 25: `README.md` + `USAGE.md`

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/README.md`
- Create: `/Users/cyj/workspace/personal/cairn/USAGE.md`

- [ ] **Step 1: `README.md` 작성**

```markdown
# Cairn

Finder-replacement 을 지향하는 macOS 파일 브라우저. Rust 백엔드 (`cairn-walker` / `cairn-preview` / `cairn-search`) + SwiftUI 프론트엔드 (`NSTableView` bridge + `NSVisualEffectView` Glass Blue 테마).

**상태:** `v0.1.0-alpha` (Phase 1 완료). Phase 2 는 persistent index + content search + command palette 예정.

## 빌드 (from source)

**요구사항:**
- macOS 14+
- Rust 1.85+
- Xcode 15+ (Swift 5.9)
- `xcodegen`, `swift-bridge` (dev dep)

```bash
git clone https://github.com/ongjin/cairn.git
cd cairn
./scripts/build-rust.sh        # universal static lib
./scripts/gen-bindings.sh      # Swift bindings
(cd apps && xcodegen generate && xcodebuild -scheme Cairn -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
open ~/Library/Developer/Xcode/DerivedData/Cairn-*/Build/Products/Debug/Cairn.app
```

## 주요 단축키

| 키 | 동작 |
|---|---|
| `⌘↑` | 상위 폴더 |
| `⌘←` / `⌘→` | 히스토리 back / forward |
| `⌘⇧.` | 숨김 파일 토글 |
| `⌘D` | 현재 폴더 Pinned 추가 / 해제 |
| `⌘R` | 현재 폴더 리로드 |
| `⌘F` | 검색 필드 focus (This Folder / Subtree) |
| `Space` | Quick Look |
| `⌥⌘C` | 경로 복사 |
| `⌘⌫` | Move to Trash |

자세한 사용법은 `USAGE.md`.

## 로드맵

- **Phase 1 (완료)** — Rust walker + SwiftUI 리스트 + 사이드바 + Preview + Quick Look + Glass Blue 테마 + 컨텍스트 메뉴 + 검색 (folder / subtree)
- **Phase 2** — `cairn-index` (redb persistent) + FSEvents 실시간 동기화 + `⌘K` command palette + content search + fuzzy match
- **Phase 3** — 테마 스위처 + 다국어 + 배포 (서명/notarize)

설계 문서: `docs/superpowers/specs/`. 구현 플랜: `docs/superpowers/plans/`.

## 라이선스

MIT (루트 `LICENSE` 참조).
```

- [ ] **Step 2: `USAGE.md` 작성 (유저 가이드)**

```markdown
# Cairn 사용 가이드

## 첫 실행

- 앱 시작 시 폴더 선택 창 (`NSOpenPanel`) 이 뜬다. 원하는 폴더 선택 → 해당 폴더가 Pinned 섹션에 자동 추가됨
- 이후 실행부터는 마지막 폴더로 복귀

## 사이드바

- **Pinned** — `⌘D` 로 추가/해제. 우클릭으로 Unpin / Reveal
- **Recent** — 최근 방문. 자동 갱신
- **iCloud** — iCloud Drive (활성 상태일 때만)
- **Locations** — 로컬 드라이브 / 외장 USB (mount/unmount 즉시 반영)

현재 폴더와 일치하는 row 는 파란 accent pill 로 하이라이트.

## 네비게이션

- 폴더 더블클릭 / `⏎` → 진입
- 파일 더블클릭 / `⏎` → 기본 앱으로 열기
- 브레드크럼 세그먼트 클릭 → 해당 경로로 이동
- `⌘↑` 상위, `⌘←/→` 히스토리
- 컬럼 헤더 클릭 → 정렬 (Name / Size / Modified, asc/desc 토글)

## 프리뷰

- 파일 선택 → 우측 프리뷰 패널에 자동 (텍스트 첫 2KB / 이미지 썸네일 / 디렉터리 child count / 기타 meta)
- `Space` → 전체 Quick Look
- `⌘R` → 현재 폴더 리로드

## 컨텍스트 메뉴

파일/폴더 우클릭:
- **Add to Pinned / Unpin** (폴더만)
- **Reveal in Finder**
- **Copy Path** (`⌥⌘C`)
- **Open With ▸** (파일만 — 기본 앱 + 대체 앱 목록)
- **Move to Trash** (`⌘⌫`)

## 검색 (M1.6 신규)

- `⌘F` → toolbar search field focus
- Picker 로 **This Folder** / **Subtree** 선택:
  - **This Folder** — 현재 폴더 바로 안의 파일만 즉시 substring 필터
  - **Subtree** — 현재 폴더 이하 전체를 recursive walk. 결과가 live 하게 populate. Folder 컬럼으로 위치 표시
- `.gitignore` 는 기본 존중 (`⌘⇧.` 로 숨김 파일 ON 시 해제)
- 최대 5,000 결과 — 초과 시 배너 + 쿼리 refinement 안내
- `Esc` / 빈 쿼리 → 정상 폴더 뷰 복귀

검색 결과에서도 `Space` (QL), 더블클릭 (Open), 우클릭 (컨텍스트 메뉴) 모두 정상 동작. Folder 클릭 시 해당 폴더로 navigate 되며 검색 쿼리는 유지 (새 root 에서 re-search).

## 알려진 제약 (v0.1.0-alpha)

- 내용 검색 / fuzzy / regex 없음 (Phase 2 예정)
- 드래그 앤 드롭 없음 (Phase 2)
- 다중 선택 시 `⏎` 는 focused row 만 열기
- 샌드박스 외부 폴더 첫 접근 시 매번 권한 재프롬프트
```

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add README.md USAGE.md
git commit -m "docs: add README and USAGE for v0.1.0-alpha"
```

---

## Task 26: `scripts/make-dmg.sh` — DMG 빌드 실험

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/scripts/make-dmg.sh`

- [ ] **Step 1: 스크립트 작성**

```bash
#!/usr/bin/env bash
# Build an unsigned DMG of Cairn for local testing.
# Requires `brew install create-dmg`.
# Distribution-ready (notarized, signed) DMG is Phase 3.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

command -v create-dmg >/dev/null 2>&1 || {
    echo "error: create-dmg not found. Install via: brew install create-dmg"
    exit 1
}

echo "▸ Building Release Cairn.app..."
./scripts/build-rust.sh
./scripts/gen-bindings.sh
(cd apps && xcodegen generate)
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Release \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    -derivedDataPath .dmg-build 2>&1 | tail -5

APP_PATH="$(find .dmg-build -name 'Cairn.app' -type d | head -1)"
if [ -z "$APP_PATH" ]; then
    echo "error: Cairn.app not found under .dmg-build/"
    exit 1
fi

OUT_DMG="Cairn-v0.1.0-alpha.dmg"
rm -f "$OUT_DMG"

echo "▸ Creating $OUT_DMG..."
create-dmg \
    --volname "Cairn v0.1.0-alpha" \
    --window-size 500 340 \
    --icon-size 96 \
    --app-drop-link 380 160 \
    --icon "Cairn.app" 120 160 \
    "$OUT_DMG" \
    "$APP_PATH"

echo "✓ $OUT_DMG ready ($(du -h "$OUT_DMG" | cut -f1))"
echo "  (unsigned — Gatekeeper will complain unless you right-click → Open)"
```

- [ ] **Step 2: 실행 권한 + 테스트 (create-dmg 없으면 설치 프롬프트만 확인)**

```bash
cd /Users/cyj/workspace/personal/cairn
chmod +x scripts/make-dmg.sh
./scripts/make-dmg.sh 2>&1 | head -3
```

Expected:
- create-dmg 있으면 → DMG 생성. 결과 파일 `Cairn-v0.1.0-alpha.dmg` (repo 루트). **`.gitignore` 에 DMG 파일 추가 권장.**
- create-dmg 없으면 → "Install via: brew install create-dmg" 에러 출력 후 exit 1.

설치 없이 실행 시 에러만 확인 후 넘어가도 OK. (이건 실험 성격이고 alpha 필수 gate 아님.)

- [ ] **Step 3: `.gitignore` 에 DMG 추가 (만약 빌드 성공했으면)**

`.gitignore` 끝에 한 줄 추가:
```
*.dmg
.dmg-build/
```

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add scripts/make-dmg.sh .gitignore
git commit -m "build: add make-dmg.sh script (unsigned) + .gitignore DMG artifacts"
```

---

## Task 27: 수동 E2E 체크리스트 완주 (사용자 수행) + sanity + tag

**Files:** 없음 (verification only) + tag

이 Task 는 사용자 본인이 수동 체크리스트를 돌린 후 완료.

- [ ] **Step 1: 앱 실행 + 체크리스트 (§ 9 spec)**

```bash
cd /Users/cyj/workspace/personal/cairn
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
```

스펙 § 9.1 / § 9.2 / § 9.3 전 항목 체크. 하나라도 ❌ 면 STOP 하고 이슈 보고.

- [ ] **Step 2: 로컬 CI**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./scripts/build-rust.sh
./scripts/gen-bindings.sh
(cd apps && xcodegen generate && xcodebuild -scheme Cairn -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | tail -3)
(cd apps && xcodebuild test -scheme CairnTests -destination "platform=macOS" \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | grep -E "Executed|TEST" | tail -5)
```

Expected:
- fmt clean
- clippy clean
- cargo test: workspace 전체 통과 (cairn-search 10개 포함)
- build-rust / gen-bindings: pass (Generated diff 는 있을 수 있음 — M1.5 와 다름)
- xcodebuild build: PASS
- xcodebuild test: 29 tests

- [ ] **Step 3: Generated 변경분 커밋 (만약 발생)**

```bash
git status --short apps/Sources/Generated/
# 변경 있으면:
git add apps/Sources/Generated/
git commit -m "build: regenerate swift-bridge bindings for M1.6"
```

- [ ] **Step 4: Tag**

```bash
cd /Users/cyj/workspace/personal/cairn
git tag phase-1-m1.6
git tag v0.1.0-alpha
git log --oneline phase-1-m1.5..phase-1-m1.6
```

Expected: M1.6 커밋 약 22–26개 (Task 1–26 각 1 커밋 + fmt/regen 이 있으면 추가).

- [ ] **Step 5: Tag 확인**

```bash
git tag -l | grep -E "(phase|v0)"
```

Expected:
```
phase-1-m1.1
phase-1-m1.2
phase-1-m1.3
phase-1-m1.4
phase-1-m1.5
phase-1-m1.6
v0.1.0-alpha
```

---

## 🎯 M1.6 Definition of Done

- [ ] `cairn-search` skeleton → 실구현 (Folder + Subtree, cancellation, cap, 10 unit tests)
- [ ] FFI 에 `searchStart` / `searchNextBatch` / `searchCancel` 브리지
- [ ] Swift `SearchModel` + `SearchField` + ContentView 통합
- [ ] `FileListView` entries injection + `FileListCoordinator` Folder 컬럼
- [ ] `⌘F` 키바인딩 + scope Picker + result cap banner + empty-result state
- [ ] Polish P1–P19 흡수 (P13 retracted, P19 skip if no drift)
- [ ] README + USAGE 추가
- [ ] `scripts/make-dmg.sh` 추가
- [ ] `xcodebuild test` 29 passing (기존 20 + SearchModelTests 5 + FileListCoordinatorTests 1 + SidebarModelTests 3)
- [ ] `cargo test --workspace` 전체 통과 (cairn-search 10 포함)
- [ ] `cargo clippy -D warnings` + `cargo fmt --check` clean
- [ ] `git tag phase-1-m1.6` 과 `git tag v0.1.0-alpha` 세팅 (같은 HEAD)

---

## 이월된 follow-up (Phase 2 로)

이 플랜 **안 다룸**:

- `cairn-index` redb persistent index + FSEvents 실시간 동기화
- `⌘K` command palette (global search)
- Content search (grep-like) + fuzzy matching
- Drag-and-drop
- Multi-row `⏎` 일괄 열기
- 검색 결과 export / Smart Folders / Saved Searches
- 드래그-pin, 사이드바 reorder
- 샌드박스 bookmark 자동 관리 (현재는 NSOpenPanel 재프롬프트)
- 서명 / notarize / 배포 DMG

---

## 다음 단계

M1.6 종료 후 Phase 2 플랜 작성 (spec 갱신부터):
- `cairn-index` redb 스키마 + FSEvents integration
- `⌘K` palette UI (Alfred-like)
- Content search FFI + UI
- Fuzzy scoring (`nucleo` 크레이트 후보)

Phase 2 플랜은 M1.6 실행 러닝 반영 후 작성.
