# Cairn Phase 1 · M1.8 — Unified Implementation Plan → `v0.1.0-alpha.2`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** M1.7 visual polish 위에 primary interaction model 을 `⌘K` palette 로 뒤집고, Phase 2 Rust foundation (cairn-index + FSEvents + git + content search + symbols) + UX 정리 (toolbar slim, sidebar Finder parity, tabs, multi-window) + bug fix (Glass, ⌘F) 를 한 마일스톤에 통합 전달.

**Architecture:** 창 = N 탭, 탭 = 1 폴더 컨텍스트 (FolderModel / SearchModel / PreviewModel / IndexService / GitService 세트 소유). `⌘K` palette 가 탭의 Index 를 쿼리하는 uniform surface. Rust 쪽은 `cairn-index` (redb + tree-sitter + nucleo) + `cairn-git` (git2) 신규 crate.

**Tech Stack:** Swift 5.9 · SwiftUI · AppKit · macOS 14 · xcodegen 2.45 | Rust 1.85 · swift-bridge 0.1.59 · **redb 2.x** · **notify 6.x** · **git2 0.18** · **tree-sitter 0.22 + 5 grammars (swift/ts/tsx/python/rust)** · ripgrep (번들 spawn)

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main, HEAD 시작 = `phase-1-m1.7` + spec `030fd8d`)

**Predecessor:** `docs/superpowers/plans/2026-04-22-cairn-phase-1-m1.7-design-polish.md` (완료, tag `phase-1-m1.7`)

**Parent spec:** `docs/superpowers/specs/2026-04-22-cairn-phase-1-m1.8-unified-design.md`

**Deliverable verification (M1.8 완료 조건):**
- `cargo fmt --check` / `cargo clippy -D warnings` / `cargo test --workspace` 전부 green (신규 crate 2 개 포함)
- `xcodebuild build` PASS, `xcodebuild test` **60+ tests**
- `build-rust.sh` + `gen-bindings.sh` 에서 Generated diff 발생 (정상 — FFI surface 확장)
- 앱 실행 → Glass 파랗게, tabs 동작, `⌘K` 5 모드, Git 컬럼, 확장된 사이드바
- `git tag phase-1-m1.8` + `git tag v0.1.0-alpha.2` (같은 HEAD)

**특이사항:**
- **FFI 변경 대폭** — Generated diff 는 이 마일스톤에 정상. M1.7 "diff 0" 제약 해제.
- **Ripgrep 바이너리 번들** — 앱 bundle 에 `Contents/Resources/rg` 포함 (~5MB).
- **Tree-sitter 5 grammars** — 로컬 첫 빌드 5–10 분 추가 예상.
- **커밋 메시지 verbatim.** 원격 push 는 수동.

---

## Task 개요 (총 19 개)

### Phase A — Rust foundation (Tasks 1–7)
1. `cairn-git` crate — snapshot + branch + tests
2. `cairn-index` 스켈레톤 + redb store + meta
3. `cairn-index` walker (files table populate)
4. `cairn-index` fuzzy query (nucleo)
5. `cairn-index` symbols (tree-sitter, 5 grammars)
6. `cairn-index` content search (ripgrep spawn + stream)
7. `cairn-index` FSEvents watch + apply_delta

### Phase B — FFI + Swift services (Tasks 8–9)
8. `cairn-ffi` bridge 확장 (IndexHandle + GitSnapshot + callback)
9. `IndexService` + `GitService` Swift 래퍼 + tests

### Phase C — 코어 리팩터 (Task 10)
10. `WindowSceneModel` + `Tab` + `AppModel` 경로 이관

### Phase D — UX 버그 + slim down (Tasks 11–12)
11. Glass Blue 실현 (material + panelTint 재조정)
12. Toolbar slim + breadcrumb 이동 + ⌘F 수정 + scope picker 제거 + `ThemedSearchField.swift` 삭제

### Phase E — Tabs UI (Task 13)
13. `TabBarView` + keyboard wiring (`⌘T/W/1-9/⌥←→/N`)

### Phase F — Palette (Tasks 14–15)
14. `CommandPaletteModel` (parse + state) + tests
15. `CommandPaletteView` overlay + 5 모드 (fuzzy / `>` / `/` / `#` / `@`)

### Phase G — 사이드바 확장 (Task 16)
16. Favorites auto 4 개 + Home + AirDrop + Trash + Network + `GitBranchFooter`

### Phase H — File list Git 컬럼 (Task 17)
17. Git 컬럼 (repo 감지 시 표시, 정렬 가능)

### Phase I — 번들링 + Finalize (Tasks 18–19)
18. Ripgrep 바이너리 번들 + project.yml Copy Files phase
19. 로컬 CI + `git tag phase-1-m1.8` + `v0.1.0-alpha.2`

---

## Task 1: `cairn-git` crate (snapshot + branch)

**Files:**
- Create: `crates/cairn-git/Cargo.toml`
- Create: `crates/cairn-git/src/lib.rs`
- Create: `crates/cairn-git/src/snapshot.rs`
- Modify: `Cargo.toml` (workspace members)

- [ ] **Step 1: Workspace 에 crate 등록**

Repo root `Cargo.toml` 의 `[workspace].members` 배열에 `"crates/cairn-git"` 추가.

- [ ] **Step 2: `crates/cairn-git/Cargo.toml` 작성**

```toml
[package]
name = "cairn-git"
version = "0.1.0"
edition = "2021"

[lib]
name = "cairn_git"
path = "src/lib.rs"

[dependencies]
git2 = { version = "0.18", default-features = false, features = ["vendored-libgit2"] }

[dev-dependencies]
tempfile = "3"
```

`vendored-libgit2` 는 시스템 libgit2 의존 없이 번들 빌드. CI 환경 단순화.

- [ ] **Step 3: 실패하는 테스트 작성**

`crates/cairn-git/src/snapshot.rs`:

```rust
use std::path::{Path, PathBuf};

/// Status for one file relative to a repository root.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileStatus {
    Modified,
    Added,
    Deleted,
    Untracked,
    Renamed,
}

#[derive(Debug, Clone)]
pub struct GitSnapshot {
    pub branch: Option<String>,
    pub modified: Vec<PathBuf>,
    pub added: Vec<PathBuf>,
    pub deleted: Vec<PathBuf>,
    pub untracked: Vec<PathBuf>,
}

pub fn snapshot(root: &Path) -> Option<GitSnapshot> {
    todo!()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::process::Command;
    use tempfile::TempDir;

    fn init_repo() -> TempDir {
        let tmp = TempDir::new().unwrap();
        Command::new("git").args(["init", "-q", "-b", "main"])
            .current_dir(tmp.path()).status().unwrap();
        Command::new("git").args(["config", "user.email", "t@t"])
            .current_dir(tmp.path()).status().unwrap();
        Command::new("git").args(["config", "user.name", "t"])
            .current_dir(tmp.path()).status().unwrap();
        tmp
    }

    #[test]
    fn not_a_repo_returns_none() {
        let tmp = TempDir::new().unwrap();
        assert!(snapshot(tmp.path()).is_none());
    }

    #[test]
    fn empty_repo_returns_branch_no_changes() {
        let tmp = init_repo();
        let snap = snapshot(tmp.path()).unwrap();
        // Brand-new repo: HEAD is unborn, branch name is still resolvable via HEAD ref target.
        assert_eq!(snap.branch.as_deref(), Some("main"));
        assert!(snap.modified.is_empty());
        assert!(snap.untracked.is_empty());
    }

    #[test]
    fn untracked_file_appears() {
        let tmp = init_repo();
        fs::write(tmp.path().join("hello.txt"), "hi").unwrap();
        let snap = snapshot(tmp.path()).unwrap();
        assert_eq!(snap.untracked.len(), 1);
        assert_eq!(snap.untracked[0], PathBuf::from("hello.txt"));
    }

    #[test]
    fn modified_file_appears() {
        let tmp = init_repo();
        fs::write(tmp.path().join("a.txt"), "orig").unwrap();
        Command::new("git").args(["add", "a.txt"]).current_dir(tmp.path()).status().unwrap();
        Command::new("git").args(["commit", "-q", "-m", "init"]).current_dir(tmp.path()).status().unwrap();
        fs::write(tmp.path().join("a.txt"), "changed").unwrap();
        let snap = snapshot(tmp.path()).unwrap();
        assert_eq!(snap.modified.len(), 1);
        assert_eq!(snap.modified[0], PathBuf::from("a.txt"));
    }
}
```

- [ ] **Step 4: `crates/cairn-git/src/lib.rs`**

```rust
pub mod snapshot;

pub use snapshot::{snapshot, GitSnapshot, FileStatus};
```

- [ ] **Step 5: 컴파일 실패 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-git 2>&1 | tail -20
```

Expected: build fails (`todo!()` in snapshot). Or panics when test runs (`not yet implemented`).

- [ ] **Step 6: `snapshot()` 구현**

```rust
use git2::{Repository, StatusOptions};

pub fn snapshot(root: &Path) -> Option<GitSnapshot> {
    let repo = Repository::discover(root).ok()?;

    // Branch name: HEAD -> resolve to ref -> shorthand.
    let branch = match repo.head() {
        Ok(head) => head.shorthand().map(String::from),
        Err(_) => {
            // Unborn HEAD — read HEAD ref target directly.
            repo.find_reference("HEAD").ok()
                .and_then(|r| r.symbolic_target().map(String::from))
                .and_then(|t| t.strip_prefix("refs/heads/").map(String::from))
        }
    };

    let mut opts = StatusOptions::new();
    opts.include_untracked(true).recurse_untracked_dirs(true);

    let mut modified = Vec::new();
    let mut added = Vec::new();
    let mut deleted = Vec::new();
    let mut untracked = Vec::new();

    let statuses = repo.statuses(Some(&mut opts)).ok()?;
    for s in statuses.iter() {
        let path = match s.path() { Some(p) => PathBuf::from(p), None => continue };
        let flags = s.status();
        if flags.intersects(git2::Status::WT_MODIFIED | git2::Status::INDEX_MODIFIED) {
            modified.push(path);
        } else if flags.intersects(git2::Status::INDEX_NEW) {
            added.push(path);
        } else if flags.intersects(git2::Status::WT_DELETED | git2::Status::INDEX_DELETED) {
            deleted.push(path);
        } else if flags.contains(git2::Status::WT_NEW) {
            untracked.push(path);
        }
    }

    Some(GitSnapshot { branch, modified, added, deleted, untracked })
}
```

- [ ] **Step 7: 테스트 통과 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-git 2>&1 | tail -10
```

Expected: 4 tests pass.

- [ ] **Step 8: 커밋**

```bash
git add crates/cairn-git Cargo.toml
git commit -m "feat(rust): add cairn-git crate with snapshot + branch"
```

---

## Task 2: `cairn-index` 스켈레톤 + redb store

**Files:**
- Create: `crates/cairn-index/Cargo.toml`
- Create: `crates/cairn-index/src/lib.rs`
- Create: `crates/cairn-index/src/store.rs`
- Modify: `Cargo.toml` (workspace members)

- [ ] **Step 1: Workspace 등록**

Repo root `Cargo.toml` 의 `[workspace].members` 에 `"crates/cairn-index"` 추가.

- [ ] **Step 2: `crates/cairn-index/Cargo.toml`**

```toml
[package]
name = "cairn-index"
version = "0.1.0"
edition = "2021"

[lib]
name = "cairn_index"
path = "src/lib.rs"

[dependencies]
redb = "2"
serde = { version = "1", features = ["derive"] }
bincode = "1.3"
sha2 = "0.10"
dirs = "5"

[dev-dependencies]
tempfile = "3"
```

- [ ] **Step 3: 실패 테스트 (store round-trip)**

`crates/cairn-index/src/store.rs`:

```rust
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FileRow {
    pub size: u64,
    pub mtime_unix: i64,
    pub kind: FileKind,
    pub git_status: Option<GitStatusByte>,
    pub symbol_count: u32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum FileKind { Regular, Directory, Symlink }

/// Single-byte git status for compact storage.
/// M=modified, A=added, D=deleted, U=untracked, R=renamed.
pub type GitStatusByte = u8;

pub struct IndexStore {
    db: redb::Database,
}

impl IndexStore {
    pub fn open(db_path: &Path) -> Result<Self, IndexError> { todo!() }
    pub fn put_file(&self, rel: &str, row: &FileRow) -> Result<(), IndexError> { todo!() }
    pub fn get_file(&self, rel: &str) -> Result<Option<FileRow>, IndexError> { todo!() }
    pub fn delete_file(&self, rel: &str) -> Result<(), IndexError> { todo!() }
    pub fn list_all(&self) -> Result<Vec<(String, FileRow)>, IndexError> { todo!() }
}

#[derive(Debug, thiserror::Error)]
pub enum IndexError {
    #[error("redb: {0}")] Db(#[from] redb::Error),
    #[error("redb transaction: {0}")] Tx(#[from] redb::TransactionError),
    #[error("redb storage: {0}")] Storage(#[from] redb::StorageError),
    #[error("redb table: {0}")] Table(#[from] redb::TableError),
    #[error("redb commit: {0}")] Commit(#[from] redb::CommitError),
    #[error("bincode: {0}")] Codec(#[from] bincode::Error),
}

/// Compute cache path under user's cache dir.
pub fn cache_path_for(root: &Path) -> PathBuf {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(root.to_string_lossy().as_bytes());
    let hash = hex::encode(hasher.finalize());
    let base = dirs::cache_dir().unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("Cairn").join("index").join(format!("{hash}.redb"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn sample() -> FileRow {
        FileRow { size: 42, mtime_unix: 1_700_000_000, kind: FileKind::Regular, git_status: None, symbol_count: 0 }
    }

    #[test]
    fn put_get_roundtrip() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("x.redb")).unwrap();
        store.put_file("foo/bar.txt", &sample()).unwrap();
        assert_eq!(store.get_file("foo/bar.txt").unwrap(), Some(sample()));
    }

    #[test]
    fn delete_removes_row() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("x.redb")).unwrap();
        store.put_file("a.txt", &sample()).unwrap();
        store.delete_file("a.txt").unwrap();
        assert!(store.get_file("a.txt").unwrap().is_none());
    }

    #[test]
    fn list_all_returns_all() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("x.redb")).unwrap();
        store.put_file("a.txt", &sample()).unwrap();
        store.put_file("b.txt", &sample()).unwrap();
        let rows = store.list_all().unwrap();
        assert_eq!(rows.len(), 2);
    }
}
```

`Cargo.toml` dependencies 에 `hex = "0.4"` 과 `thiserror = "1"` 추가.

- [ ] **Step 4: `lib.rs`**

```rust
pub mod store;

pub use store::{IndexStore, FileRow, FileKind, IndexError, cache_path_for};
```

- [ ] **Step 5: 컴파일 실패 확인**

```bash
cargo test -p cairn-index 2>&1 | tail -10
```

Expected: `todo!()` panics or compile errors.

- [ ] **Step 6: `IndexStore` 구현**

```rust
const TABLE_FILES: redb::TableDefinition<&str, &[u8]> = redb::TableDefinition::new("files");

impl IndexStore {
    pub fn open(db_path: &Path) -> Result<Self, IndexError> {
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let db = redb::Database::create(db_path).map_err(|e| IndexError::Db(e.into()))?;
        // Ensure table exists.
        let tx = db.begin_write()?;
        {
            let _ = tx.open_table(TABLE_FILES)?;
        }
        tx.commit()?;
        Ok(Self { db })
    }

    pub fn put_file(&self, rel: &str, row: &FileRow) -> Result<(), IndexError> {
        let bytes = bincode::serialize(row)?;
        let tx = self.db.begin_write()?;
        {
            let mut t = tx.open_table(TABLE_FILES)?;
            t.insert(rel, bytes.as_slice())?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn get_file(&self, rel: &str) -> Result<Option<FileRow>, IndexError> {
        let tx = self.db.begin_read()?;
        let t = tx.open_table(TABLE_FILES)?;
        match t.get(rel)? {
            Some(bytes) => Ok(Some(bincode::deserialize(bytes.value())?)),
            None => Ok(None),
        }
    }

    pub fn delete_file(&self, rel: &str) -> Result<(), IndexError> {
        let tx = self.db.begin_write()?;
        {
            let mut t = tx.open_table(TABLE_FILES)?;
            t.remove(rel)?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn list_all(&self) -> Result<Vec<(String, FileRow)>, IndexError> {
        let tx = self.db.begin_read()?;
        let t = tx.open_table(TABLE_FILES)?;
        let mut out = Vec::new();
        for entry in t.iter()? {
            let (k, v) = entry?;
            let row: FileRow = bincode::deserialize(v.value())?;
            out.push((k.value().to_string(), row));
        }
        Ok(out)
    }
}
```

Add `use redb::ReadableTable;` at top of file for iteration.

Note: redb 2.x 의 에러 타입 이름은 버전에 따라 다를 수 있음. 첫 빌드 후 컴파일러 메시지에 맞춰 `#[from]` 추가.

- [ ] **Step 7: 테스트 통과**

```bash
cargo test -p cairn-index 2>&1 | tail -10
```

Expected: 3 tests pass.

- [ ] **Step 8: 커밋**

```bash
git add crates/cairn-index Cargo.toml
git commit -m "feat(rust): add cairn-index crate with redb store"
```

---

## Task 3: `cairn-index` walker (populate files table)

**Files:**
- Create: `crates/cairn-index/src/walker.rs`
- Modify: `crates/cairn-index/src/lib.rs`
- Modify: `crates/cairn-index/Cargo.toml` (cairn-engine + cairn-git dep)

- [ ] **Step 1: Cargo.toml 확장**

```toml
[dependencies]
# ... 기존 ...
cairn-engine = { path = "../cairn-engine" }
cairn-git = { path = "../cairn-git" }
walkdir = "2"
```

- [ ] **Step 2: 실패 테스트**

`crates/cairn-index/src/walker.rs`:

```rust
use crate::store::{FileRow, FileKind, IndexStore};
use std::path::Path;

pub fn walk_into(root: &Path, store: &IndexStore) -> Result<usize, crate::IndexError> {
    todo!()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn walk_populates_store_with_regular_files() {
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("a.txt"), "aaa").unwrap();
        fs::write(tmp.path().join("b.swift"), "bb").unwrap();
        fs::create_dir(tmp.path().join("sub")).unwrap();
        fs::write(tmp.path().join("sub/c.md"), "c").unwrap();

        let db_tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&db_tmp.path().join("i.redb")).unwrap();
        let count = walk_into(tmp.path(), &store).unwrap();
        assert_eq!(count, 4); // 2 files + 1 dir + 1 file

        let all = store.list_all().unwrap();
        assert!(all.iter().any(|(p, _)| p == "a.txt"));
        assert!(all.iter().any(|(p, r)| p == "sub" && matches!(r.kind, FileKind::Directory)));
        assert!(all.iter().any(|(p, _)| p == "sub/c.md"));
    }

    #[test]
    fn walk_skips_dotgit() {
        let tmp = TempDir::new().unwrap();
        fs::create_dir(tmp.path().join(".git")).unwrap();
        fs::write(tmp.path().join(".git/HEAD"), "ref").unwrap();
        fs::write(tmp.path().join("x.txt"), "x").unwrap();

        let db_tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&db_tmp.path().join("i.redb")).unwrap();
        walk_into(tmp.path(), &store).unwrap();

        let all = store.list_all().unwrap();
        assert!(all.iter().all(|(p, _)| !p.starts_with(".git")));
        assert!(all.iter().any(|(p, _)| p == "x.txt"));
    }
}
```

- [ ] **Step 3: 컴파일 실패 확인**

```bash
cargo test -p cairn-index walker::tests 2>&1 | tail -10
```

Expected: `todo!()` panic.

- [ ] **Step 4: `walk_into` 구현**

```rust
use walkdir::WalkDir;
use std::os::unix::fs::MetadataExt;

pub fn walk_into(root: &Path, store: &IndexStore) -> Result<usize, crate::IndexError> {
    let git_snap = cairn_git::snapshot(root);
    let git_status_for = |rel: &str| -> Option<u8> {
        let snap = git_snap.as_ref()?;
        let pb = std::path::PathBuf::from(rel);
        if snap.modified.contains(&pb)  { Some(b'M') }
        else if snap.added.contains(&pb)    { Some(b'A') }
        else if snap.deleted.contains(&pb)  { Some(b'D') }
        else if snap.untracked.contains(&pb){ Some(b'U') }
        else { None }
    };

    let mut count = 0;
    for entry in WalkDir::new(root).follow_links(false).into_iter().filter_entry(|e| {
        // Skip .git at any depth
        e.file_name().to_string_lossy() != ".git"
    }) {
        let entry = match entry { Ok(e) => e, Err(_) => continue };
        if entry.depth() == 0 { continue; } // skip root itself

        let rel = match entry.path().strip_prefix(root) {
            Ok(r) => r.to_string_lossy().into_owned(),
            Err(_) => continue,
        };
        let ft = entry.file_type();
        let kind = if ft.is_dir() { FileKind::Directory }
                   else if ft.is_symlink() { FileKind::Symlink }
                   else { FileKind::Regular };
        let md = match entry.metadata() { Ok(m) => m, Err(_) => continue };
        let row = FileRow {
            size: md.len(),
            mtime_unix: md.mtime(),
            kind,
            git_status: git_status_for(&rel),
            symbol_count: 0,
        };
        store.put_file(&rel, &row)?;
        count += 1;
    }
    Ok(count)
}
```

- [ ] **Step 5: `lib.rs` 에 `pub mod walker; pub use walker::walk_into;` 추가**

- [ ] **Step 6: 테스트 통과**

```bash
cargo test -p cairn-index 2>&1 | tail -10
```

Expected: 5 tests pass (3 store + 2 walker).

- [ ] **Step 7: 커밋**

```bash
git add crates/cairn-index
git commit -m "feat(rust): add walker that populates index with file rows"
```

---

## Task 4: `cairn-index` fuzzy query (nucleo)

**Files:**
- Create: `crates/cairn-index/src/fuzzy.rs`
- Modify: `crates/cairn-index/src/lib.rs`
- Modify: `crates/cairn-index/Cargo.toml`

- [ ] **Step 1: deps**

```toml
[dependencies]
# ... 기존 ...
nucleo-matcher = "0.3"
```

- [ ] **Step 2: 실패 테스트**

`crates/cairn-index/src/fuzzy.rs`:

```rust
use crate::store::IndexStore;

#[derive(Debug, Clone)]
pub struct FileHit {
    pub path_rel: String,
    pub score: u32,
    /// Byte offsets in path_rel that matched, used by UI for highlighting.
    pub matches: Vec<u32>,
}

pub fn query(store: &IndexStore, needle: &str, limit: usize) -> Result<Vec<FileHit>, crate::IndexError> {
    todo!()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::{FileRow, FileKind, IndexStore};
    use tempfile::TempDir;

    fn sample(store: &IndexStore, paths: &[&str]) {
        for p in paths {
            let row = FileRow {
                size: 0, mtime_unix: 0, kind: FileKind::Regular,
                git_status: None, symbol_count: 0,
            };
            store.put_file(p, &row).unwrap();
        }
    }

    #[test]
    fn empty_needle_returns_all_up_to_limit() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("i.redb")).unwrap();
        sample(&store, &["a.txt", "b.txt", "c.txt"]);
        let hits = query(&store, "", 2).unwrap();
        assert_eq!(hits.len(), 2);
    }

    #[test]
    fn fuzzy_ranks_substring_higher() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("i.redb")).unwrap();
        sample(&store, &["foo.txt", "barfoo.txt", "unrelated.txt"]);
        let hits = query(&store, "foo", 10).unwrap();
        assert_eq!(hits[0].path_rel, "foo.txt");
        assert!(hits.iter().any(|h| h.path_rel == "barfoo.txt"));
        assert!(hits.iter().all(|h| h.path_rel != "unrelated.txt"));
    }
}
```

- [ ] **Step 3: 구현**

```rust
use nucleo_matcher::{Matcher, Config, Utf32Str, pattern::{Pattern, CaseMatching, Normalization}};

pub fn query(store: &IndexStore, needle: &str, limit: usize) -> Result<Vec<FileHit>, crate::IndexError> {
    let rows = store.list_all()?;

    if needle.is_empty() {
        return Ok(rows.into_iter().take(limit).map(|(p, _)| FileHit {
            path_rel: p, score: 0, matches: Vec::new(),
        }).collect());
    }

    let mut matcher = Matcher::new(Config::DEFAULT);
    let pattern = Pattern::parse(needle, CaseMatching::Smart, Normalization::Smart);

    let mut scored: Vec<FileHit> = rows.iter().filter_map(|(path, _)| {
        let mut buf = Vec::new();
        let hay = Utf32Str::new(path, &mut buf);
        let mut indices: Vec<u32> = Vec::new();
        let score = pattern.indices(hay, &mut matcher, &mut indices)?;
        Some(FileHit { path_rel: path.clone(), score: score as u32, matches: indices })
    }).collect();

    scored.sort_by(|a, b| b.score.cmp(&a.score));
    scored.truncate(limit);
    Ok(scored)
}
```

- [ ] **Step 4: `lib.rs`** 에 `pub mod fuzzy; pub use fuzzy::{query as query_fuzzy, FileHit};` 추가

- [ ] **Step 5: 테스트 + 커밋**

```bash
cargo test -p cairn-index 2>&1 | tail -10
```

Expected: 7 tests pass.

```bash
git add crates/cairn-index
git commit -m "feat(rust): add fuzzy query via nucleo-matcher"
```

---

## Task 5: `cairn-index` symbols (tree-sitter, 5 grammars)

**Files:**
- Create: `crates/cairn-index/src/symbols.rs`
- Modify: `crates/cairn-index/src/lib.rs`
- Modify: `crates/cairn-index/src/walker.rs` (symbol extraction hook)
- Modify: `crates/cairn-index/Cargo.toml`

- [ ] **Step 1: deps**

```toml
[dependencies]
# ... 기존 ...
tree-sitter = "0.22"
tree-sitter-swift = "0.4"
tree-sitter-typescript = "0.23"
tree-sitter-python = "0.23"
tree-sitter-rust = "0.23"
# NOTE: typescript 크레이트에 tsx 가 포함됨 — 별도 의존 불필요 (1 grammar 맵핑에서 tsx 분기).
```

> 주의: tree-sitter grammar crate 버전은 시간이 지나며 바뀜. 각 크레이트의 실제 최신 stable 확인 후 반영.

- [ ] **Step 2: 실패 테스트**

`crates/cairn-index/src/symbols.rs`:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SymbolRow {
    pub name: String,
    pub kind: SymbolKind,
    pub line: u32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum SymbolKind {
    Class, Struct, Enum, Function, Method, Variable, Constant, Interface,
}

pub fn extract_from_file(path: &std::path::Path) -> Vec<SymbolRow> {
    todo!()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn swift_extracts_class_and_func() {
        let tmp = TempDir::new().unwrap();
        let p = tmp.path().join("x.swift");
        fs::write(&p, "class Foo { func bar() {} }").unwrap();
        let syms = extract_from_file(&p);
        let names: Vec<&str> = syms.iter().map(|s| s.name.as_str()).collect();
        assert!(names.contains(&"Foo"));
        assert!(names.contains(&"bar"));
    }

    #[test]
    fn rust_extracts_fn_and_struct() {
        let tmp = TempDir::new().unwrap();
        let p = tmp.path().join("x.rs");
        fs::write(&p, "struct Foo; fn bar() {}").unwrap();
        let syms = extract_from_file(&p);
        let names: Vec<&str> = syms.iter().map(|s| s.name.as_str()).collect();
        assert!(names.contains(&"Foo"));
        assert!(names.contains(&"bar"));
    }

    #[test]
    fn unsupported_language_returns_empty() {
        let tmp = TempDir::new().unwrap();
        let p = tmp.path().join("x.xyz");
        fs::write(&p, "nothing").unwrap();
        assert!(extract_from_file(&p).is_empty());
    }
}
```

- [ ] **Step 3: 구현**

```rust
use tree_sitter::{Parser, Language, Query, QueryCursor, Node};

fn lang_for_ext(ext: &str) -> Option<(Language, &'static str)> {
    match ext {
        "swift" => Some((tree_sitter_swift::language(), SWIFT_Q)),
        "ts"    => Some((tree_sitter_typescript::language_typescript(), TS_Q)),
        "tsx"   => Some((tree_sitter_typescript::language_tsx(), TS_Q)),
        "py"    => Some((tree_sitter_python::language(), PY_Q)),
        "rs"    => Some((tree_sitter_rust::language(), RUST_Q)),
        _ => None,
    }
}

const SWIFT_Q: &str = r#"
(class_declaration name: (type_identifier) @class)
(protocol_declaration name: (type_identifier) @interface)
(function_declaration name: (simple_identifier) @function)
"#;
const TS_Q: &str = r#"
(class_declaration name: (type_identifier) @class)
(interface_declaration name: (type_identifier) @interface)
(function_declaration name: (identifier) @function)
(method_definition name: (property_identifier) @method)
"#;
const PY_Q: &str = r#"
(class_definition name: (identifier) @class)
(function_definition name: (identifier) @function)
"#;
const RUST_Q: &str = r#"
(struct_item name: (type_identifier) @struct)
(enum_item name: (type_identifier) @enum)
(function_item name: (identifier) @function)
(impl_item) @method
"#;

fn kind_from_capture(name: &str) -> SymbolKind {
    match name {
        "class" => SymbolKind::Class,
        "struct" => SymbolKind::Struct,
        "enum" => SymbolKind::Enum,
        "interface" => SymbolKind::Interface,
        "function" => SymbolKind::Function,
        "method" => SymbolKind::Method,
        _ => SymbolKind::Variable,
    }
}

pub fn extract_from_file(path: &std::path::Path) -> Vec<SymbolRow> {
    let ext = match path.extension().and_then(|e| e.to_str()) {
        Some(e) => e,
        None => return Vec::new(),
    };
    let (lang, query_src) = match lang_for_ext(ext) { Some(x) => x, None => return Vec::new() };
    let src = match std::fs::read_to_string(path) { Ok(s) => s, Err(_) => return Vec::new() };

    let mut parser = Parser::new();
    if parser.set_language(&lang).is_err() { return Vec::new(); }
    let tree = match parser.parse(&src, None) { Some(t) => t, None => return Vec::new() };
    let query = match Query::new(&lang, query_src) { Ok(q) => q, Err(_) => return Vec::new() };

    let mut cursor = QueryCursor::new();
    let capture_names = query.capture_names();
    let mut out = Vec::new();
    for mat in cursor.matches(&query, tree.root_node(), src.as_bytes()) {
        for cap in mat.captures {
            let node: Node = cap.node;
            let cap_name = capture_names[cap.index as usize];
            let name = match node.utf8_text(src.as_bytes()) {
                Ok(n) => n.to_string(),
                Err(_) => continue,
            };
            out.push(SymbolRow {
                name,
                kind: kind_from_capture(cap_name),
                line: node.start_position().row as u32 + 1,
            });
        }
    }
    out
}
```

- [ ] **Step 4: redb table for symbols**

`store.rs` 에 추가:

```rust
const TABLE_SYMBOLS: redb::TableDefinition<(&str, u32), &[u8]> = redb::TableDefinition::new("symbols");

impl IndexStore {
    pub fn put_symbols(&self, rel: &str, syms: &[crate::symbols::SymbolRow]) -> Result<(), IndexError> {
        let tx = self.db.begin_write()?;
        {
            let mut t = tx.open_table(TABLE_SYMBOLS)?;
            // Clear existing for this file.
            // redb 2.x lacks prefix delete; iterate and remove.
            let keys: Vec<(String, u32)> = {
                let read = t.iter()?;
                read.filter_map(|e| e.ok().map(|(k,_)| (k.value().0.to_string(), k.value().1))).collect()
            };
            for (p, idx) in keys.iter().filter(|(p, _)| p == rel) {
                t.remove((p.as_str(), *idx))?;
            }
            for (i, s) in syms.iter().enumerate() {
                let bytes = bincode::serialize(s)?;
                t.insert((rel, i as u32), bytes.as_slice())?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    pub fn query_symbols(&self, needle: &str, limit: usize) -> Result<Vec<(String, crate::symbols::SymbolRow)>, IndexError> {
        let tx = self.db.begin_read()?;
        let t = tx.open_table(TABLE_SYMBOLS)?;
        let mut out = Vec::new();
        for entry in t.iter()? {
            let (k, v) = entry?;
            let (rel, _idx) = k.value();
            let row: crate::symbols::SymbolRow = bincode::deserialize(v.value())?;
            if needle.is_empty() || row.name.to_lowercase().contains(&needle.to_lowercase()) {
                out.push((rel.to_string(), row));
            }
            if out.len() >= limit { break; }
        }
        Ok(out)
    }
}
```

- [ ] **Step 5: walker 에 symbol extraction hook**

`walker.rs` 수정 — regular file 이면 symbols 뽑아서 store 에 put:

```rust
// 기존 put_file 바로 뒤
if matches!(kind, FileKind::Regular) {
    let syms = crate::symbols::extract_from_file(entry.path());
    if !syms.is_empty() {
        store.put_symbols(&rel, &syms).ok();
    }
}
```

- [ ] **Step 6: `lib.rs` 추가**

```rust
pub mod symbols;
pub use symbols::{SymbolRow, SymbolKind};
```

- [ ] **Step 7: 테스트 + 커밋**

```bash
cargo test -p cairn-index 2>&1 | tail -10
```

Expected: 10 tests pass (7 + 3 symbols).

```bash
git add crates/cairn-index
git commit -m "feat(rust): add tree-sitter symbol extraction for 5 grammars"
```

---

## Task 6: `cairn-index` content search (ripgrep spawn + stream)

**Files:**
- Create: `crates/cairn-index/src/content.rs`
- Modify: `crates/cairn-index/src/lib.rs`
- Modify: `crates/cairn-index/Cargo.toml`

- [ ] **Step 1: deps**

```toml
[dependencies]
# ... 기존 ...
serde_json = "1"
```

- [ ] **Step 2: 실패 테스트**

`crates/cairn-index/src/content.rs`:

```rust
use std::path::Path;
use std::sync::mpsc;

#[derive(Debug, Clone, PartialEq)]
pub struct ContentHit {
    pub path_rel: String,
    pub line: u32,
    pub preview: String,
}

pub struct ContentSearch {
    handle: Option<std::thread::JoinHandle<()>>,
    cancel: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl ContentSearch {
    pub fn spawn(
        rg_binary: &Path,
        root: &Path,
        pattern: &str,
        on_hit: impl Fn(ContentHit) + Send + 'static,
    ) -> Self {
        todo!()
    }

    pub fn cancel(&mut self) {
        todo!()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use tempfile::TempDir;

    fn which_rg() -> Option<std::path::PathBuf> {
        let out = std::process::Command::new("which").arg("rg").output().ok()?;
        if !out.status.success() { return None; }
        let s = String::from_utf8(out.stdout).ok()?;
        let trimmed = s.trim();
        if trimmed.is_empty() { None } else { Some(trimmed.into()) }
    }

    #[test]
    fn finds_hits_in_tmp_dir() {
        let rg = match which_rg() { Some(p) => p, None => { eprintln!("skip: rg not installed"); return; } };
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("a.txt"), "hello world\nfoo bar\n").unwrap();

        let counter = Arc::new(AtomicUsize::new(0));
        let c = counter.clone();
        let search = ContentSearch::spawn(&rg, tmp.path(), "hello", move |_| {
            c.fetch_add(1, Ordering::SeqCst);
        });
        // Simple wait; real code uses a callback-with-done.
        std::thread::sleep(std::time::Duration::from_millis(500));
        drop(search); // joins
        assert_eq!(counter.load(Ordering::SeqCst), 1);
    }
}
```

- [ ] **Step 3: 구현**

```rust
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio, Child};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

impl ContentSearch {
    pub fn spawn(
        rg_binary: &Path,
        root: &Path,
        pattern: &str,
        on_hit: impl Fn(ContentHit) + Send + 'static,
    ) -> Self {
        let cancel = Arc::new(AtomicBool::new(false));
        let cancel_thr = cancel.clone();
        let rg_path = rg_binary.to_path_buf();
        let root_path = root.to_path_buf();
        let pat = pattern.to_string();

        let handle = std::thread::spawn(move || {
            let mut child: Child = match Command::new(&rg_path)
                .args(["--json", "--max-count", "200"])
                .arg(&pat)
                .arg(&root_path)
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
            {
                Ok(c) => c,
                Err(_) => return,
            };

            let stdout = match child.stdout.take() { Some(s) => s, None => { let _ = child.kill(); return; } };
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                if cancel_thr.load(Ordering::SeqCst) { let _ = child.kill(); break; }
                let line = match line { Ok(l) => l, Err(_) => continue };
                let val: serde_json::Value = match serde_json::from_str(&line) { Ok(v) => v, Err(_) => continue };
                if val["type"] != "match" { continue; }
                let data = &val["data"];
                let path = data["path"]["text"].as_str().unwrap_or("").to_string();
                let line_num = data["line_number"].as_u64().unwrap_or(0) as u32;
                let preview = data["lines"]["text"].as_str().unwrap_or("").trim_end().to_string();
                // path is absolute; strip root to get relative.
                let rel = match Path::new(&path).strip_prefix(&root_path) {
                    Ok(r) => r.to_string_lossy().into_owned(),
                    Err(_) => path,
                };
                on_hit(ContentHit { path_rel: rel, line: line_num, preview });
            }
            let _ = child.wait();
        });

        Self { handle: Some(handle), cancel }
    }

    pub fn cancel(&mut self) {
        self.cancel.store(true, Ordering::SeqCst);
    }
}

impl Drop for ContentSearch {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::SeqCst);
        if let Some(h) = self.handle.take() { let _ = h.join(); }
    }
}
```

- [ ] **Step 4: `lib.rs` 추가**

```rust
pub mod content;
pub use content::{ContentSearch, ContentHit};
```

- [ ] **Step 5: 테스트**

로컬에 `rg` 있으면 통과, 없으면 skip. CI 환경에서는 번들 rg 를 쓸 예정이지만 이 테스트는 시스템 rg 로 smoke.

```bash
cargo test -p cairn-index 2>&1 | tail -10
```

Expected: 11 tests (10 + 1, 단 `rg` 있을 때만 — 없으면 print "skip: rg not installed" 후 PASS).

- [ ] **Step 6: 커밋**

```bash
git add crates/cairn-index
git commit -m "feat(rust): add ripgrep-based content search with cancel"
```

---

## Task 7: `cairn-index` FSEvents watch + apply_delta

**Files:**
- Create: `crates/cairn-index/src/watch.rs`
- Modify: `crates/cairn-index/src/lib.rs`
- Modify: `crates/cairn-index/Cargo.toml`

- [ ] **Step 1: deps**

```toml
[dependencies]
# ... 기존 ...
notify = "6"
notify-debouncer-mini = "0.4"
```

- [ ] **Step 2: 실패 테스트**

`crates/cairn-index/src/watch.rs`:

```rust
use crate::store::IndexStore;
use std::path::Path;
use std::sync::mpsc;
use std::time::Duration;

pub struct Watcher {
    _inner: Box<dyn std::any::Any + Send>,
}

pub fn watch(root: &Path, store: std::sync::Arc<IndexStore>) -> notify::Result<Watcher> {
    todo!()
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
        // Debounced ~200ms + processing.
        std::thread::sleep(Duration::from_millis(800));

        let got = store.get_file("added.txt").unwrap();
        assert!(got.is_some(), "FSEvents-driven index update should have added 'added.txt'");
    }
}
```

FSEvents 테스트는 macOS 타이밍에 민감. 실패하면 sleep 값 키우기.

- [ ] **Step 3: 구현**

```rust
use notify_debouncer_mini::{new_debouncer, DebouncedEventKind};
use std::os::unix::fs::MetadataExt;
use std::path::PathBuf;
use std::sync::Arc;
use crate::store::{FileRow, FileKind};

pub fn watch(root: &Path, store: Arc<IndexStore>) -> notify::Result<Watcher> {
    let root = root.to_path_buf();
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
```

- [ ] **Step 4: `lib.rs` 추가**

```rust
pub mod watch;
pub use watch::{watch, Watcher};
```

- [ ] **Step 5: 테스트 + 커밋**

```bash
cargo test -p cairn-index 2>&1 | tail -10
```

Expected: 12 tests (11 + 1 watch smoke).

```bash
git add crates/cairn-index
git commit -m "feat(rust): add FSEvents watcher with debounced index updates"
```

---

## Task 8: FFI bridge 확장 (IndexHandle + GitSnapshot)

**Files:**
- Modify: `crates/cairn-ffi/Cargo.toml`
- Create: `crates/cairn-ffi/src/index.rs`
- Create: `crates/cairn-ffi/src/git.rs`
- Modify: `crates/cairn-ffi/src/lib.rs`
- Modify: `crates/cairn-ffi/build.rs`

> **Note:** cairn-ffi 의 현재 구조 확인 필요. `build.rs` 가 swift-bridge 를 어떻게 호출하는지 따라가서 신규 모듈의 bridge 선언을 포함시켜야 함. 기존 `cairn_ffi.swift` 의 구조를 모방.

- [ ] **Step 1: Cargo.toml 확장**

`crates/cairn-ffi/Cargo.toml` `[dependencies]` 에:

```toml
cairn-index = { path = "../cairn-index" }
cairn-git = { path = "../cairn-git" }
```

- [ ] **Step 2: `src/git.rs`**

```rust
use cairn_git::snapshot;
use std::path::Path;

#[swift_bridge::bridge]
mod ffi {
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
```

- [ ] **Step 3: `src/index.rs`**

IndexHandle 은 opaque. swift-bridge 의 `Box<dyn ...>` 전달 제약 때문에, **global registry** 패턴 으로 uint64 ID 를 Swift 에 주고 Swift 는 ID 로만 참조.

```rust
use cairn_index::{IndexStore, walk_into, query_fuzzy, FileHit, cache_path_for, Watcher, watch};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::path::PathBuf;

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
    struct FfiFileHit {
        path_rel: String,
        score: u32,
    }

    struct FfiSymbolHit {
        path_rel: String,
        name: String,
        kind_raw: u8,   // SymbolKind as byte
        line: u32,
    }

    extern "Rust" {
        fn ffi_index_open(root: String) -> u64;   // returns handle id; 0 on failure
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
    // Initial walk synchronously (small folders) — M1.8 후속으로 background 화 가능.
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
    for p in snap.modified.iter().chain(snap.untracked.iter()).chain(snap.added.iter()) {
        out.push(ffi::FfiFileHit { path_rel: p.to_string_lossy().into_owned(), score: 0 });
    }
    out
}
```

> Content search 는 Rust→Swift callback 이 swift-bridge 에서 복잡 → **이 task 에서는 fuzzy/symbol/git 만 먼저 bridge**. Content 는 Task 8b 로 분리. 단순화를 위해 Task 8 안에서 같은 커밋에 묶자 — 실제 content_search 콜백은 swift-bridge 의 `Box<dyn Fn>` 패턴 대신 **polling 방식** 으로 (Swift 가 spawn 후 일정 간격으로 `ffi_content_poll` 호출해 버퍼를 비움).

- [ ] **Step 4: content search polling 방식 추가**

`src/index.rs` 에 이어서:

```rust
use std::sync::mpsc::{channel, Receiver, Sender};
use cairn_index::ContentSearch;

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
    struct FfiContentHit {
        path_rel: String,
        line: u32,
        preview: String,
    }

    extern "Rust" {
        fn ffi_content_start(handle: u64, pattern: String) -> u64;  // session id; 0 on fail
        fn ffi_content_poll(session: u64, max: u32) -> Vec<FfiContentHit>;
        fn ffi_content_cancel(session: u64);
    }
}

pub fn ffi_content_start(handle: u64, pattern: String) -> u64 {
    // Locate rg binary: prefer CAIRN_RG_PATH env (set by app at runtime to bundled path), fall back to $PATH.
    let rg_path = match std::env::var("CAIRN_RG_PATH") {
        Ok(p) => PathBuf::from(p),
        Err(_) => match which::which("rg") { Ok(p) => p, Err(_) => return 0 },
    };
    let reg = registry().lock().unwrap();
    let entry = match reg.get(&handle) { Some(e) => e, None => return 0 };
    let (tx, rx): (Sender<_>, Receiver<_>) = channel();
    let search = ContentSearch::spawn(&rg_path, &entry.root, &pattern, move |hit| { let _ = tx.send(hit); });
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
```

Cargo.toml 에 `which = "6"` 추가.

- [ ] **Step 5: `src/lib.rs` 에 mod 추가**

```rust
pub mod index;
pub mod git;
```

- [ ] **Step 6: `build.rs` 확인**

기존 `build.rs` 가 어떻게 swift-bridge 를 호출하는지 확인 후, 신규 모듈 (`index`, `git`) 의 bridge 도 include. 대개 swift-bridge-build crate 가 source 파일 리스트를 받음.

- [ ] **Step 7: `build-rust.sh` + `gen-bindings.sh` 돌려서 Generated 재생성**

```bash
cd /Users/cyj/workspace/personal/cairn
./scripts/build-rust.sh
./scripts/gen-bindings.sh
git status --short apps/Sources/Generated/
```

Expected: Generated diff 큼 — 신규 bridge 타입/함수 추가됨. M1.8 에선 정상.

- [ ] **Step 8: 전체 rust test 통과 확인**

```bash
cargo test --workspace 2>&1 | tail -20
```

Expected: cairn-git 4 + cairn-index 12 + 기존 엔진 테스트 = 총 20+ green.

- [ ] **Step 9: 커밋 (2 개로 분리)**

```bash
git add crates/cairn-ffi
git commit -m "feat(ffi): add IndexHandle + GitSnapshot + content session bridges"

git add apps/Sources/Generated/
git commit -m "build: regenerate Swift bindings for M1.8 FFI surface"
```

---

## Task 9: Swift `IndexService` + `GitService` + tests

**Files:**
- Create: `apps/Sources/Services/IndexService.swift`
- Create: `apps/Sources/Services/GitService.swift`
- Create: `apps/CairnTests/IndexServiceTests.swift`
- Create: `apps/CairnTests/GitServiceTests.swift`

- [ ] **Step 1: IndexService 작성**

```swift
import Foundation
import Observation

/// Swift wrapper around the Rust `IndexHandle`. One instance per Tab.
/// Owns the handle lifecycle via open/close.
@Observable
final class IndexService {
    private let handle: UInt64
    let root: URL

    init?(root: URL) {
        self.root = root
        let id = ffi_index_open(root.path)
        guard id != 0 else { return nil }
        self.handle = id
    }

    deinit {
        ffi_index_close(handle)
    }

    func queryFuzzy(_ query: String, limit: Int = 50) -> [FileHit] {
        let hits = ffi_index_query_fuzzy(handle, query, UInt32(limit))
        return hits.map { FileHit(pathRel: $0.path_rel.toString(), score: Int($0.score)) }
    }

    func querySymbols(_ query: String, limit: Int = 50) -> [SymbolHit] {
        let hits = ffi_index_query_symbols(handle, query, UInt32(limit))
        return hits.map { SymbolHit(pathRel: $0.path_rel.toString(), name: $0.name.toString(),
                                    kind: SymbolKind(rawByte: $0.kind_raw), line: Int($0.line)) }
    }

    func queryGitDirty() -> [FileHit] {
        let hits = ffi_index_query_git_dirty(handle)
        return hits.map { FileHit(pathRel: $0.path_rel.toString(), score: 0) }
    }

    func startContent(pattern: String) -> ContentSearchSession? {
        let sid = ffi_content_start(handle, pattern)
        guard sid != 0 else { return nil }
        return ContentSearchSession(sessionID: sid)
    }
}

struct FileHit: Identifiable, Hashable {
    let pathRel: String
    let score: Int
    var id: String { pathRel }
}

struct SymbolHit: Identifiable, Hashable {
    let pathRel: String
    let name: String
    let kind: SymbolKind
    let line: Int
    var id: String { "\(pathRel):\(line):\(name)" }
}

enum SymbolKind: UInt8 {
    case klass = 0, strct = 1, enm = 2, function = 3, method = 4, variable = 5, constant = 6, interface = 7, unknown = 255
    init(rawByte: UInt8) { self = SymbolKind(rawValue: rawByte) ?? .unknown }
}

/// Polling-based stream for content search results.
final class ContentSearchSession {
    private let sessionID: UInt64
    private(set) var results: [ContentHit] = []

    init(sessionID: UInt64) { self.sessionID = sessionID }
    deinit { ffi_content_cancel(sessionID) }

    func poll(max: Int = 50) -> [ContentHit] {
        let hits = ffi_content_poll(sessionID, UInt32(max))
        let mapped = hits.map { ContentHit(pathRel: $0.path_rel.toString(), line: Int($0.line), preview: $0.preview.toString()) }
        results.append(contentsOf: mapped)
        return mapped
    }

    func cancel() { ffi_content_cancel(sessionID) }
}

struct ContentHit: Identifiable, Hashable {
    let pathRel: String
    let line: Int
    let preview: String
    var id: String { "\(pathRel):\(line)" }
}
```

- [ ] **Step 2: GitService**

```swift
import Foundation
import Observation

@Observable
final class GitService {
    let root: URL
    private(set) var snapshot: Snapshot?

    struct Snapshot {
        let branch: String?
        let modifiedCount: Int
        let untrackedCount: Int
        let addedCount: Int
        let deletedCount: Int
        var dirtyCount: Int { modifiedCount + untrackedCount + addedCount + deletedCount }
    }

    init(root: URL) {
        self.root = root
        refresh()
    }

    /// Synchronous — libgit2 under the hood. Call from main, debounced by caller.
    func refresh() {
        let s = ffi_git_snapshot(root.path)
        guard let s else { self.snapshot = nil; return }
        let branch = s.branch.toString()
        self.snapshot = Snapshot(
            branch: branch.isEmpty ? nil : branch,
            modifiedCount: Int(s.modified_count),
            untrackedCount: Int(s.untracked_count),
            addedCount: Int(s.added_count),
            deletedCount: Int(s.deleted_count)
        )
    }
}
```

- [ ] **Step 3: 테스트**

`apps/CairnTests/IndexServiceTests.swift`:

```swift
import XCTest
@testable import Cairn

final class IndexServiceTests: XCTestCase {
    private func tmpDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func test_open_returns_service() {
        let d = tmpDir()
        defer { try? FileManager.default.removeItem(at: d) }
        try! "hi".write(to: d.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let svc = IndexService(root: d)
        XCTAssertNotNil(svc)
    }

    func test_query_fuzzy_returns_hits() {
        let d = tmpDir()
        defer { try? FileManager.default.removeItem(at: d) }
        try! "x".write(to: d.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try! "y".write(to: d.appendingPathComponent("world.txt"), atomically: true, encoding: .utf8)
        let svc = IndexService(root: d)!
        let hits = svc.queryFuzzy("hell", limit: 10)
        XCTAssertTrue(hits.contains { $0.pathRel == "hello.txt" })
    }
}
```

`apps/CairnTests/GitServiceTests.swift`:

```swift
import XCTest
@testable import Cairn

final class GitServiceTests: XCTestCase {
    func test_non_repo_snapshot_is_nil() {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        let svc = GitService(root: d)
        XCTAssertNil(svc.snapshot)
    }

    func test_fresh_repo_snapshot_has_branch() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        // shell out to git init
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = ["git", "init", "-q", "-b", "main", d.path]
        try p.run(); p.waitUntilExit()

        let svc = GitService(root: d)
        XCTAssertNotNil(svc.snapshot)
        XCTAssertEqual(svc.snapshot?.branch, "main")
    }
}
```

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 38/38 tests pass (M1.7 34 + 4 new: 2 index + 2 git).

- [ ] **Step 5: 커밋**

```bash
git add apps/Sources/Services/IndexService.swift apps/Sources/Services/GitService.swift \
        apps/CairnTests/IndexServiceTests.swift apps/CairnTests/GitServiceTests.swift
git commit -m "feat(services): add IndexService and GitService Swift wrappers"
```

---

## Task 10: `WindowSceneModel` + `Tab` + AppModel 경로 이관

**Files:**
- Create: `apps/Sources/ViewModels/Tab.swift`
- Create: `apps/Sources/ViewModels/WindowSceneModel.swift`
- Create: `apps/CairnTests/TabTests.swift`
- Create: `apps/CairnTests/WindowSceneModelTests.swift`
- Modify: `apps/Sources/App/AppModel.swift` (currentFolder 제거 + helper 이관)
- Modify: `apps/Sources/ContentView.swift` (activeTab 라우팅)
- Modify: `apps/Sources/CairnApp.swift` (WindowSceneModel 주입)
- Modify: `apps/Sources/Views/Sidebar/SidebarView.swift` (activeTab 참조)
- Modify: `apps/Sources/Views/Sidebar/BreadcrumbBar.swift` (activeTab 참조)

> **큰 리팩터 task** — 신중히. 아래는 구조 중심, 세부 step 은 많음. TDD 보다는 "컴파일 통과 + 기존 동작 회귀 없음" 중심. 각 파일 수정 후 `xcodebuild build` 돌려서 에러 하나씩 해결.

- [ ] **Step 1: Tab 타입 작성**

```swift
import Foundation
import Observation

/// One tab's full state: folder, search, preview, index, git.
/// Owns the IndexService/GitService lifecycle for that tab's current folder.
@Observable
final class Tab: Identifiable {
    let id = UUID()

    let folder: FolderModel
    let search: SearchModel
    let preview: PreviewModel
    private(set) var index: IndexService?
    private(set) var git: GitService?

    /// Per-tab navigation history (independent of sibling tabs).
    var history = NavigationHistory()

    init(engine: CairnEngine, initialURL: URL) {
        self.folder = FolderModel(engine: engine)
        self.search = SearchModel(engine: engine)
        self.preview = PreviewModel(engine: engine)
        self.history.push(initialURL)
        rebuildServices(for: initialURL)
    }

    var currentFolder: URL? { history.current }

    func navigate(to url: URL) {
        history.push(url)
        rebuildServices(for: url)
    }

    func goBack() -> URL? {
        let u = history.goBack()
        if let u { rebuildServices(for: u) }
        return u
    }

    func goForward() -> URL? {
        let u = history.goForward()
        if let u { rebuildServices(for: u) }
        return u
    }

    func goUp() {
        guard let cur = currentFolder else { return }
        let parent = cur.deletingLastPathComponent()
        guard parent.path != cur.path else { return }
        navigate(to: parent)
    }

    private func rebuildServices(for url: URL) {
        index = IndexService(root: url)
        git = GitService(root: url)
    }
}
```

- [ ] **Step 2: WindowSceneModel**

```swift
import Foundation
import Observation

/// Per-window state: an ordered list of tabs + active tab index.
/// Injected into ContentView via @Environment.
@Observable
final class WindowSceneModel {
    private(set) var tabs: [Tab] = []
    var activeTabID: Tab.ID?

    let engine: CairnEngine

    init(engine: CairnEngine, initialURL: URL) {
        self.engine = engine
        let first = Tab(engine: engine, initialURL: initialURL)
        self.tabs = [first]
        self.activeTabID = first.id
    }

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    func newTab(cloningActive: Bool = true) {
        let url = cloningActive ? (activeTab?.currentFolder ?? FileManager.default.homeDirectoryForCurrentUser) : FileManager.default.homeDirectoryForCurrentUser
        let t = Tab(engine: engine, initialURL: url)
        tabs.append(t)
        activeTabID = t.id
    }

    func closeTab(_ id: Tab.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if activeTabID == id {
            activeTabID = tabs.last?.id
        }
    }

    func activateTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeTabID = tabs[index].id
    }

    func activatePrevious() {
        guard let cur = activeTabID, let idx = tabs.firstIndex(where: { $0.id == cur }) else { return }
        let prev = idx == 0 ? tabs.count - 1 : idx - 1
        activeTabID = tabs[prev].id
    }

    func activateNext() {
        guard let cur = activeTabID, let idx = tabs.firstIndex(where: { $0.id == cur }) else { return }
        let next = (idx + 1) % tabs.count
        activeTabID = tabs[next].id
    }
}
```

- [ ] **Step 3: 테스트**

`apps/CairnTests/TabTests.swift`:

```swift
import XCTest
@testable import Cairn

final class TabTests: XCTestCase {
    func test_initial_url_is_in_history() {
        let t = Tab(engine: CairnEngine(), initialURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(t.currentFolder?.path, "/tmp")
    }

    func test_navigate_pushes_history() {
        let t = Tab(engine: CairnEngine(), initialURL: URL(fileURLWithPath: "/tmp"))
        t.navigate(to: URL(fileURLWithPath: "/usr"))
        XCTAssertEqual(t.currentFolder?.path, "/usr")
    }

    func test_goBack_returns_previous_url() {
        let t = Tab(engine: CairnEngine(), initialURL: URL(fileURLWithPath: "/tmp"))
        t.navigate(to: URL(fileURLWithPath: "/usr"))
        XCTAssertEqual(t.goBack()?.path, "/tmp")
    }
}
```

`apps/CairnTests/WindowSceneModelTests.swift`:

```swift
import XCTest
@testable import Cairn

final class WindowSceneModelTests: XCTestCase {
    func test_initial_has_one_tab() {
        let m = WindowSceneModel(engine: CairnEngine(), initialURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(m.tabs.count, 1)
        XCTAssertNotNil(m.activeTab)
    }

    func test_newTab_appends_and_activates() {
        let m = WindowSceneModel(engine: CairnEngine(), initialURL: URL(fileURLWithPath: "/tmp"))
        m.newTab()
        XCTAssertEqual(m.tabs.count, 2)
        XCTAssertEqual(m.activeTabID, m.tabs[1].id)
    }

    func test_closeTab_picks_remaining_tab() {
        let m = WindowSceneModel(engine: CairnEngine(), initialURL: URL(fileURLWithPath: "/tmp"))
        m.newTab()
        let closedID = m.tabs[1].id
        m.closeTab(closedID)
        XCTAssertEqual(m.tabs.count, 1)
        XCTAssertNotNil(m.activeTabID)
        XCTAssertNotEqual(m.activeTabID, closedID)
    }

    func test_activatePrevious_wraps() {
        let m = WindowSceneModel(engine: CairnEngine(), initialURL: URL(fileURLWithPath: "/tmp"))
        m.newTab()
        m.activateTab(at: 0)
        m.activatePrevious()
        XCTAssertEqual(m.activeTabID, m.tabs[1].id)
    }
}
```

- [ ] **Step 4: `AppModel` slim down**

`AppModel` 에서 tab-specific 함수 제거:
- `navigate(to:)`, `navigateUnscoped(to:)`, `goBack()`, `goForward()`, `goUp()`, `currentFolder` computed, `currentEntry`, `history`, `reopenCurrentFolder(onPick:)` 등은 `Tab` 으로 이관. AppModel 에 남기는 것은 app 전역 (engine, bookmarks, lastFolder, mountObserver, sidebar model, preview — preview 도 per-tab 으로 이동했으니 제거).

새로운 `AppModel` 모양:

```swift
@Observable
final class AppModel {
    let engine: CairnEngine
    let bookmarks: BookmarkStore
    let lastFolder: LastFolderStore
    let mountObserver: MountObserver
    let sidebar: SidebarModel
    var showHidden: Bool = false

    init(engine: CairnEngine = CairnEngine(),
         bookmarks: BookmarkStore = BookmarkStore(),
         lastFolder: LastFolderStore = LastFolderStore()) {
        self.engine = engine
        self.bookmarks = bookmarks
        self.lastFolder = lastFolder
        let observer = MountObserver()
        self.mountObserver = observer
        self.sidebar = SidebarModel(mountObserver: observer)
    }

    func toggleShowHidden() {
        showHidden.toggle()
        engine.setShowHidden(showHidden)
    }

    @MainActor
    func reopenCurrentFolder(onPick: @escaping @MainActor (URL) -> Void) {
        // 그대로 유지 (panel + onPick) — 이건 global UI 관심사.
    }

    func bootstrapInitialURL() -> URL {
        lastFolder.load() ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
```

`BookmarkEntry.kind == .pinned` 자동 추가 로직은 callers (ContentView.handleOpen 등) 로 분산. 또는 Tab 에서 navigate 시 bookmark 등록 호출.

- [ ] **Step 5: `CairnApp` 에 WindowSceneModel 주입**

```swift
@main
struct CairnApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            WindowScene(app: app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Task 13 에서 확장
        }
    }
}

struct WindowScene: View {
    let app: AppModel
    @State private var scene: WindowSceneModel

    init(app: AppModel) {
        self.app = app
        _scene = State(initialValue: WindowSceneModel(engine: app.engine, initialURL: app.bootstrapInitialURL()))
    }

    var body: some View {
        ContentView()
            .environment(app)
            .environment(scene)
            .environment(\.cairnTheme, .glass)
            .frame(minWidth: 800, minHeight: 500)
            .background(VisualEffectBlur(material: .hudWindow).ignoresSafeArea()) // Task 11 에서 교체
    }
}
```

- [ ] **Step 6: `ContentView` 재라우팅**

기존 `folder`/`searchModel` state 제거. `scene.activeTab` 에서 직접 읽음. `SidebarView`, `BreadcrumbBar` 도 `scene.activeTab` 참조하도록 수정.

(구체 diff 는 길어서 생략 — 컴파일러 에러 따라가며 수정. 각 call site 에서 `app.currentFolder` → `scene.activeTab?.currentFolder`, `app.navigate(to:)` → `scene.activeTab?.navigate(to:)` 등.)

- [ ] **Step 7: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 빌드 성공, **45/45 tests** (38 + 7 new: 3 tab + 4 scene).

- [ ] **Step 8: 커밋**

```bash
git add .
git commit -m "refactor(app): introduce WindowSceneModel + Tab for per-window state"
```

---

## Task 11: Glass Blue 실현

**Files:**
- Modify: `apps/Sources/Theme/CairnTheme.swift`
- Modify: `apps/Sources/CairnApp.swift` (material 교체)
- Modify: `apps/Sources/ContentView.swift` (fileList overlay opacity 재조정)

- [ ] **Step 1: `CairnTheme.swift` panelTint 교체**

```swift
extension CairnTheme {
    static let glass = CairnTheme(
        id: "glass",
        displayName: "Glass (Blue)",
        windowMaterial: .sidebar,                              // was .hudWindow
        sidebarTint: Color(hue: 0.62, saturation: 0.08, brightness: 0.14),
        panelTint:   Color(hue: 0.60, saturation: 0.45, brightness: 0.55, opacity: 0.25),  // 실제 파란 hue + 알파 포함
        text:          Color(white: 0.93),
        textSecondary: Color(white: 0.60),
        textTertiary:  Color(white: 0.42),
        accent:        Color(red: 0.04, green: 0.52, blue: 1.00),
        accentMuted:   Color(red: 0.04, green: 0.52, blue: 1.00, opacity: 0.22),
        selectionFg:   .white,
        cornerRadius: 6,
        rowHeight: 24,
        sidebarRowHeight: 22,
        panelPadding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
        bodyFont:   .system(size: 12),
        monoFont:   .system(size: 11, design: .monospaced),
        headerFont: .system(size: 10, weight: .semibold),
        layout: .threePane
    )
}
```

- [ ] **Step 2: `CairnApp.swift` window material 교체**

`WindowScene.body` 의 `.background(VisualEffectBlur(material: .hudWindow)...)` 를 `.background(VisualEffectBlur(material: theme.windowMaterial)...)` 로 교체 — `@Environment(\.cairnTheme)` 주입 방식이 필요. 단순하게:

```swift
.background(VisualEffectBlur(material: .sidebar).ignoresSafeArea())
```

(theme 을 경유하지 않고 직접 지정. Phase 3 theme switcher 때 리팩터.)

- [ ] **Step 3: `ContentView.swift` 의 fileList overlay 알파 재조정**

기존:
```swift
.background {
    ZStack {
        VisualEffectBlur(material: .contentBackground)
        theme.panelTint.opacity(0.55)
    }
    .ignoresSafeArea()
}
```

교체 (panelTint 자체에 opacity 포함된 새 토큰 사용):
```swift
.background {
    ZStack {
        VisualEffectBlur(material: .contentBackground)
        theme.panelTint  // opacity 0.25 이미 포함
    }
    .ignoresSafeArea()
}
```

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -3
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 45/45 pass.

- [ ] **Step 5: E2E 수동 검증**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1) && open "$APP"
```

- [ ] 파일 리스트 영역에 **실제 파란 기운** 보임 (블랙 아님)
- [ ] 사이드바도 약간 파란 틴트
- [ ] 텍스트 가독성 OK (다크/라이트 둘 다 체크)

문제 있으면 `panelTint` 의 `saturation` / `brightness` / `opacity` 미세 조정.

- [ ] **Step 6: 커밋**

```bash
git add apps/Sources/Theme/CairnTheme.swift apps/Sources/CairnApp.swift apps/Sources/ContentView.swift
git commit -m "fix(theme): make Glass Blue actually blue (sidebar material + tinted panelTint)"
```

---

## Task 12: Toolbar slim + breadcrumb 이동 + ⌘F 수정 + scope picker 제거 + ThemedSearchField 삭제

**Files:**
- Modify: `apps/Sources/ContentView.swift`
- Delete: `apps/Sources/Views/Search/ThemedSearchField.swift`
- Modify: `apps/Sources/Views/Search/BreadcrumbBar.swift` (placement 변경 없음, 참조만 바꿈)
- Modify: `apps/Sources/ViewModels/SearchModel.swift` (scope 기본값 `.subtree`)

- [ ] **Step 1: `ContentView.mainToolbar` 재구성**

기존 toolbar 에서 pin / eye / reload / search field 전부 제거. Breadcrumb 을 `.principal` → `.navigation` 으로. 새로 추가: `⌘K` 힌트 chip.

```swift
@ToolbarContentBuilder
private var mainToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
        Button(action: { scene.activeTab?.goBack() }) {
            Image(systemName: "chevron.left")
        }
        .disabled(scene.activeTab?.history.canGoBack == false)
        .keyboardShortcut(.leftArrow, modifiers: [.command])

        Button(action: { scene.activeTab?.goForward() }) {
            Image(systemName: "chevron.right")
        }
        .disabled(scene.activeTab?.history.canGoForward == false)
        .keyboardShortcut(.rightArrow, modifiers: [.command])

        Button(action: { scene.activeTab?.goUp() }) {
            Image(systemName: "arrow.up")
        }
        .keyboardShortcut(.upArrow, modifiers: [.command])

        BreadcrumbBar(tab: scene.activeTab)  // was ToolbarItem(placement: .principal)
    }

    ToolbarItem(placement: .primaryAction) {
        Button(action: { paletteHint.open() }) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Text("⌘K")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}
```

`paletteHint` 는 task 14 의 CommandPaletteModel 인스턴스 — 이 task 에서는 **버튼만 껍데기**. 실제 오픈 동작은 task 15 에서 연결.

Pin / eye / reload 는 CommandMenu (task 13) 로 이관.

- [ ] **Step 2: `ThemedSearchField.swift` 삭제**

```bash
git rm apps/Sources/Views/Search/ThemedSearchField.swift
```

ContentView toolbar 에서 `ThemedSearchField(...)` / `searchFocused` state / ⌘F hidden Button 전부 제거.

- [ ] **Step 3: `BreadcrumbBar` 수정**

기존 `BreadcrumbBar(app: app)` → `BreadcrumbBar(tab: scene.activeTab)`. BreadcrumbBar 내부도 `app.currentFolder` 경로를 `tab.currentFolder` 로 바꾸고 navigate 경로를 `tab.navigate(to:)` 로.

(파일 전체 비교 생략 — 3 곳 call site 교체.)

- [ ] **Step 4: `SearchModel` scope 기본값**

```swift
var scope: Scope = .subtree   // was .folder
```

- [ ] **Step 5: ⌘F CommandMenu (Task 13 에서 구현) 준비**

이 task 에서는 toolbar 에서 hidden Button 제거만. ⌘F 실제 바인딩은 task 13 의 `.commands` CommandMenu 에서.

- [ ] **Step 6: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 45/45 (변경 없음 — UI 토크바).

- [ ] **Step 7: 커밋**

```bash
git add apps/Sources/ContentView.swift apps/Sources/ViewModels/SearchModel.swift \
        apps/Sources/Views/Sidebar/BreadcrumbBar.swift
git rm apps/Sources/Views/Search/ThemedSearchField.swift
git commit -m "refactor(toolbar): slim down (remove pin/eye/reload/search field); move breadcrumb"
```

---

## Task 13: `TabBarView` + keyboard wiring (`⌘T/W/1-9/⌥←→/N`)

**Files:**
- Create: `apps/Sources/Views/Tabs/TabBarView.swift`
- Create: `apps/Sources/Views/Tabs/TabChip.swift`
- Modify: `apps/Sources/ContentView.swift` (TabBarView overlay)
- Modify: `apps/Sources/CairnApp.swift` (.commands { CommandGroup + CommandMenu })

- [ ] **Step 1: `TabChip.swift`**

```swift
import SwiftUI

struct TabChip: View {
    let label: String
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void

    @Environment(\.cairnTheme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
            if hovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? theme.accentMuted : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? theme.accent.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { hovering = $0 }
        .frame(maxWidth: 180)
    }
}
```

- [ ] **Step 2: `TabBarView.swift`**

```swift
import SwiftUI

struct TabBarView: View {
    @Bindable var scene: WindowSceneModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(scene.tabs) { tab in
                TabChip(
                    label: tab.currentFolder?.lastPathComponent ?? "Untitled",
                    isActive: tab.id == scene.activeTabID,
                    onActivate: { scene.activeTabID = tab.id },
                    onClose: { scene.closeTab(tab.id) }
                )
            }
            Button(action: { scene.newTab() }) {
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(.thinMaterial)
    }
}
```

- [ ] **Step 3: `ContentView` 에 `TabBarView` 얹기**

`body` 최상위 구조를 `VStack(spacing: 0) { TabBarView; NavigationSplitView { ... } }` 로. 단 탭이 1 개일 때는 탭 bar 숨기기 옵션:

```swift
var body: some View {
    VStack(spacing: 0) {
        if scene.tabs.count > 1 {
            TabBarView(scene: scene)
        }
        NavigationSplitView { ... } content: { ... } detail: { ... }
    }
}
```

(단순화를 위해 항상 표시해도 무방.)

- [ ] **Step 4: `CairnApp.swift` `.commands` CommandMenu**

```swift
.commands {
    // File menu additions
    CommandGroup(after: .newItem) {
        Button("New Tab") { /* via FocusedValue */ }
            .keyboardShortcut("t", modifiers: [.command])
        Button("Close Tab") { }
            .keyboardShortcut("w", modifiers: [.command])
    }

    // Navigation
    CommandMenu("Navigate") {
        Button("Next Tab")     { }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        Button("Previous Tab") { }.keyboardShortcut(.leftArrow,  modifiers: [.command, .option])

        Divider()

        ForEach(1...9, id: \.self) { n in
            Button("Tab \(n)") { }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [.command])
        }

        Divider()

        Button("Reload")              { }.keyboardShortcut("r", modifiers: [.command])
        Button("Toggle Hidden Files") { }.keyboardShortcut(".", modifiers: [.command, .shift])
        Button("Pin Current Folder")  { }.keyboardShortcut("d", modifiers: [.command])
    }

    // Find
    CommandGroup(after: .textEditing) {
        Button("Find…") { }.keyboardShortcut("f", modifiers: [.command])
    }
}
```

> **주의**: SwiftUI `.commands` 의 Button action 은 `@FocusedValue` / `@FocusedObject` 패턴으로 활성 창의 scene 을 가져와야 동작. 구현 패턴:

```swift
// WindowScene 에 FocusedValue 게시
struct FocusedSceneKey: FocusedValueKey { typealias Value = WindowSceneModel }
extension FocusedValues { var scene: WindowSceneModel? { get { self[FocusedSceneKey.self] } set { self[FocusedSceneKey.self] = newValue } } }

// WindowScene body 에 .focusedSceneValue(\.scene, scene) 추가

// CommandMenu 에서
struct NavigateCommands: Commands {
    @FocusedValue(\.scene) var scene: WindowSceneModel?

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Next Tab") { scene?.activateNext() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(scene == nil || (scene?.tabs.count ?? 0) < 2)
            // ...
        }
    }
}
```

각 메뉴 구조체를 별도 struct 로 추출하면 가독성 좋음.

- [ ] **Step 5: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 45/45.

- [ ] **Step 6: E2E 수동**

- [ ] ⌘T → 새 탭, 활성화됨
- [ ] ⌘W → 탭 닫힘; 마지막이면 창 닫힘
- [ ] ⌘1..9 → 해당 탭
- [ ] ⌘⌥←/→ → prev / next
- [ ] ⌘R / ⌘⇧. / ⌘D → 기존 동작
- [ ] ⌘F → (task 15 이전이라 아직 아무 일도 안 일어나도 됨, menu 에 disabled 나 placeholder 허용)

- [ ] **Step 7: 커밋**

```bash
git add apps/Sources/Views/Tabs apps/Sources/ContentView.swift apps/Sources/CairnApp.swift
git commit -m "feat(tabs): add TabBarView + keyboard shortcuts via CommandMenu"
```

---

## Task 14: `CommandPaletteModel` (parse + state) + tests

**Files:**
- Create: `apps/Sources/ViewModels/CommandPaletteModel.swift`
- Create: `apps/CairnTests/CommandPaletteModelTests.swift`

- [ ] **Step 1: 실패 테스트**

```swift
import XCTest
@testable import Cairn

final class CommandPaletteModelTests: XCTestCase {
    func test_parse_empty_is_fuzzy() {
        XCTAssertEqual(CommandPaletteModel.parse(""), .fuzzy(""))
    }

    func test_parse_plain_is_fuzzy() {
        XCTAssertEqual(CommandPaletteModel.parse("hello"), .fuzzy("hello"))
    }

    func test_parse_gt_is_command() {
        XCTAssertEqual(CommandPaletteModel.parse(">new tab"), .command("new tab"))
    }

    func test_parse_slash_is_content() {
        XCTAssertEqual(CommandPaletteModel.parse("/class Foo"), .content("class Foo"))
    }

    func test_parse_hash_is_git_dirty() {
        XCTAssertEqual(CommandPaletteModel.parse("#foo"), .gitDirty("foo"))
    }

    func test_parse_at_is_symbol() {
        XCTAssertEqual(CommandPaletteModel.parse("@Bar"), .symbol("Bar"))
    }
}
```

- [ ] **Step 2: 구현**

```swift
import Foundation
import Observation

@Observable
final class CommandPaletteModel {
    enum ParsedQuery: Equatable {
        case fuzzy(String)
        case command(String)
        case content(String)
        case gitDirty(String)
        case symbol(String)
    }

    var isOpen: Bool = false
    var query: String = ""
    var selectedIndex: Int = 0

    // Results — populated by mode-specific queries (Task 15).
    var fileHits: [FileHit] = []
    var commandHits: [PaletteCommand] = []
    var contentHits: [ContentHit] = []
    var symbolHits: [SymbolHit] = []

    var contentSession: ContentSearchSession?

    static func parse(_ raw: String) -> ParsedQuery {
        if raw.isEmpty { return .fuzzy("") }
        let first = raw.first!
        let rest = String(raw.dropFirst())
        switch first {
        case ">": return .command(rest)
        case "/": return .content(rest)
        case "#": return .gitDirty(rest)
        case "@": return .symbol(rest)
        default:  return .fuzzy(raw)
        }
    }

    func open(preFocusFuzzy: Bool = false) {
        isOpen = true
        if preFocusFuzzy, query.isEmpty {
            // placeholder behavior differs for ⌘F vs ⌘K but internal state identical
        }
    }

    func close() {
        isOpen = false
        query = ""
        selectedIndex = 0
        fileHits = []
        commandHits = []
        contentHits = []
        symbolHits = []
        contentSession?.cancel()
        contentSession = nil
    }
}

struct PaletteCommand: Identifiable, Hashable {
    let id: String
    let label: String
    let iconSF: String
    let shortcutHint: String?
    let run: () -> Void

    static func == (l: PaletteCommand, r: PaletteCommand) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
```

- [ ] **Step 3: 빌드 + 테스트 + 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 51/51 (45 + 6 new).

```bash
git add apps/Sources/ViewModels/CommandPaletteModel.swift apps/CairnTests/CommandPaletteModelTests.swift
git commit -m "feat(palette): add CommandPaletteModel with prefix parser"
```

---

## Task 15: `CommandPaletteView` overlay + 5 모드 wiring

**Files:**
- Create: `apps/Sources/Views/Palette/CommandPaletteView.swift`
- Create: `apps/Sources/Views/Palette/PaletteRow.swift`
- Modify: `apps/Sources/ContentView.swift` (overlay + ⌘K/⌘F action hookup)
- Modify: `apps/Sources/ViewModels/CommandPaletteModel.swift` (dispatch 메서드 추가)

- [ ] **Step 1: `CommandPaletteModel` 에 dispatch 추가**

```swift
func dispatch(tab: Tab, query raw: String, onCommand commands: [PaletteCommand]) {
    self.query = raw
    self.selectedIndex = 0
    let parsed = Self.parse(raw)

    switch parsed {
    case .fuzzy(let q):
        fileHits = tab.index?.queryFuzzy(q, limit: 50) ?? []
        commandHits = []; contentHits = []; symbolHits = []
        contentSession?.cancel(); contentSession = nil
    case .command(let q):
        commandHits = commands.filter { q.isEmpty || $0.label.localizedCaseInsensitiveContains(q) }
        fileHits = []; contentHits = []; symbolHits = []
        contentSession?.cancel(); contentSession = nil
    case .content(let pat):
        contentSession?.cancel()
        contentHits = []
        if !pat.isEmpty, let s = tab.index?.startContent(pattern: pat) {
            contentSession = s
            // poll loop kicks off in view
        }
        fileHits = []; commandHits = []; symbolHits = []
    case .gitDirty(let q):
        let dirty = tab.index?.queryGitDirty() ?? []
        fileHits = q.isEmpty ? dirty : dirty.filter { $0.pathRel.localizedCaseInsensitiveContains(q) }
        commandHits = []; contentHits = []; symbolHits = []
        contentSession?.cancel(); contentSession = nil
    case .symbol(let q):
        symbolHits = tab.index?.querySymbols(q, limit: 50) ?? []
        fileHits = []; commandHits = []; contentHits = []
        contentSession?.cancel(); contentSession = nil
    }
}

func pollContent() {
    guard let s = contentSession else { return }
    let new = s.poll(max: 20)
    contentHits.append(contentsOf: new)
}
```

- [ ] **Step 2: `PaletteRow.swift`**

```swift
import SwiftUI

enum PaletteRowData {
    case file(FileHit)
    case command(PaletteCommand)
    case content(ContentHit)
    case symbol(SymbolHit)
}

struct PaletteRow: View {
    let data: PaletteRowData
    let isSelected: Bool
    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(theme.bodyFont.weight(.medium))
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? theme.accentMuted : Color.clear)
    }

    private var icon: Image {
        switch data {
        case .file: return Image(systemName: "doc")
        case .command(let c): return Image(systemName: c.iconSF)
        case .content: return Image(systemName: "text.magnifyingglass")
        case .symbol: return Image(systemName: "chevron.left.forwardslash.chevron.right")
        }
    }

    private var title: String {
        switch data {
        case .file(let f): return (f.pathRel as NSString).lastPathComponent
        case .command(let c): return c.label
        case .content(let h): return (h.pathRel as NSString).lastPathComponent
        case .symbol(let s): return s.name
        }
    }

    private var hint: String? {
        switch data {
        case .file(let f):
            let parent = (f.pathRel as NSString).deletingLastPathComponent
            return parent.isEmpty ? nil : parent
        case .command: return nil
        case .content(let h): return "\(h.pathRel):\(h.line) · \(h.preview)"
        case .symbol(let s): return "\(s.pathRel):\(s.line) · \(String(describing: s.kind))"
        }
    }

    private var shortcut: String? {
        if case .command(let c) = data { return c.shortcutHint }
        return nil
    }
}
```

- [ ] **Step 3: `CommandPaletteView.swift`**

```swift
import SwiftUI

struct CommandPaletteView: View {
    @Bindable var model: CommandPaletteModel
    let tab: Tab
    let commands: [PaletteCommand]
    let onActivate: (PaletteRowData) -> Void

    @Environment(\.cairnTheme) private var theme
    @FocusState private var queryFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { model.close() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(modeSigil)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 20)
                    TextField(placeholder, text: Binding(
                        get: { model.query },
                        set: { model.dispatch(tab: tab, query: $0, onCommand: commands) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($queryFocused)
                    .onSubmit { activateSelected() }
                    .onKeyPress(.downArrow) { model.selectedIndex = min(model.selectedIndex + 1, rowCount - 1); return .handled }
                    .onKeyPress(.upArrow) { model.selectedIndex = max(model.selectedIndex - 1, 0); return .handled }
                    .onKeyPress(.escape) { model.close(); return .handled }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.regularMaterial)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { (idx, row) in
                            PaletteRow(data: row, isSelected: idx == model.selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { onActivate(row) }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .background(.regularMaterial)
            }
            .frame(width: 640, height: 400, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.2), lineWidth: 1))
            .shadow(radius: 12)
            .onAppear { queryFocused = true }
            .onChange(of: model.query) { _, _ in
                // start content poll timer for / mode
            }
        }
    }

    private var rows: [PaletteRowData] {
        if !model.commandHits.isEmpty { return model.commandHits.map { .command($0) } }
        if !model.contentHits.isEmpty { return model.contentHits.map { .content($0) } }
        if !model.symbolHits.isEmpty  { return model.symbolHits.map  { .symbol($0) } }
        return model.fileHits.map { .file($0) }
    }

    private var rowCount: Int { rows.count }

    private var modeSigil: String {
        switch CommandPaletteModel.parse(model.query) {
        case .fuzzy:    return "›"
        case .command:  return ">"
        case .content:  return "/"
        case .gitDirty: return "#"
        case .symbol:   return "@"
        }
    }

    private var placeholder: String {
        switch CommandPaletteModel.parse(model.query) {
        case .fuzzy:    return "Find files…"
        case .command:  return "Run command…"
        case .content:  return "Search file contents…"
        case .gitDirty: return "Filter dirty files…"
        case .symbol:   return "Jump to symbol…"
        }
    }

    private func activateSelected() {
        guard model.selectedIndex < rows.count else { return }
        onActivate(rows[model.selectedIndex])
    }
}
```

- [ ] **Step 4: `ContentView` 에 overlay 추가 + ⌘K/⌘F 바인딩**

```swift
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(WindowSceneModel.self) private var scene
    @Environment(\.cairnTheme) private var theme
    @State private var palette = CommandPaletteModel()
    @State private var pollTimer: Timer?

    var body: some View {
        ZStack {
            // 기존 body (toolbar + sidebar + content + preview)
            NavigationSplitView { ... }
            .toolbar { mainToolbar }

            if palette.isOpen, let tab = scene.activeTab {
                CommandPaletteView(
                    model: palette,
                    tab: tab,
                    commands: builtinCommands(),
                    onActivate: handlePaletteActivate
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: palette.isOpen)
        .focusedSceneValue(\.paletteModel, palette)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            if case .content = CommandPaletteModel.parse(palette.query) {
                palette.pollContent()
            }
        }
    }

    private func builtinCommands() -> [PaletteCommand] {
        guard let tab = scene.activeTab else { return [] }
        return [
            PaletteCommand(id: "newTab", label: "New Tab", iconSF: "plus.square", shortcutHint: "⌘T") { scene.newTab() },
            PaletteCommand(id: "closeTab", label: "Close Tab", iconSF: "xmark.square", shortcutHint: "⌘W") {
                if let id = scene.activeTabID { scene.closeTab(id) }
            },
            PaletteCommand(id: "reload", label: "Reload", iconSF: "arrow.clockwise", shortcutHint: "⌘R") {
                if let u = tab.currentFolder { Task { await tab.folder.load(u) } }
            },
            PaletteCommand(id: "toggleHidden", label: "Toggle Hidden Files", iconSF: "eye", shortcutHint: "⌘⇧.") {
                app.toggleShowHidden()
            },
            PaletteCommand(id: "pinFolder", label: "Pin Current Folder", iconSF: "pin", shortcutHint: "⌘D") {
                if let u = tab.currentFolder { try? app.bookmarks.togglePin(url: u) }
            },
            PaletteCommand(id: "goUp", label: "Go to Parent Folder", iconSF: "arrow.up", shortcutHint: "⌘↑") {
                tab.goUp()
            },
        ]
    }

    private func handlePaletteActivate(_ data: PaletteRowData) {
        switch data {
        case .file(let f):
            if let tab = scene.activeTab {
                let url = tab.currentFolder?.appendingPathComponent(f.pathRel) ?? URL(fileURLWithPath: f.pathRel)
                openURL(url, tab: tab)
            }
        case .command(let c):
            c.run()
        case .content(let h):
            if let tab = scene.activeTab {
                let url = tab.currentFolder?.appendingPathComponent(h.pathRel) ?? URL(fileURLWithPath: h.pathRel)
                openURL(url, tab: tab)
                // Line 스크롤 은 M2.x 로 이월 (PreviewModel.targetLine 확장 필요). 이 plan 의
                // "이월된 follow-up" 섹션 참고. 현재는 파일만 열고 Preview pane 의 기본
                // 위치 (top) 에 표시.
            }
        case .symbol(let s):
            if let tab = scene.activeTab {
                let url = tab.currentFolder?.appendingPathComponent(s.pathRel) ?? URL(fileURLWithPath: s.pathRel)
                openURL(url, tab: tab)
            }
        }
        palette.close()
    }

    private func openURL(_ url: URL, tab: Tab) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            tab.navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// FocusedValue
struct PaletteModelKey: FocusedValueKey { typealias Value = CommandPaletteModel }
extension FocusedValues {
    var paletteModel: CommandPaletteModel? {
        get { self[PaletteModelKey.self] }
        set { self[PaletteModelKey.self] = newValue }
    }
}
```

- [ ] **Step 5: `CairnApp.swift` Find 메뉴 와이어링**

```swift
struct FindCommands: Commands {
    @FocusedValue(\.paletteModel) var palette: CommandPaletteModel?
    var body: some Commands {
        CommandGroup(replacing: .textEditing) {
            Button("Find…") { palette?.open(preFocusFuzzy: true) }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(palette == nil)
            Button("Open Palette") { palette?.open() }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(palette == nil)
        }
    }
}
```

`CairnApp.body.commands` 에 `FindCommands()` 추가.

- [ ] **Step 6: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 51/51 pass.

- [ ] **Step 7: E2E 수동**

- [ ] ⌘K → 중앙 palette 열림, input 에 포커스
- [ ] 입력 시 파일 리스트 fuzzy 결과 표시
- [ ] `>new` → commands 모드, "New Tab" 선택 시 새 탭 생김
- [ ] `/hello` → 내용 검색 결과 (현재 폴더 subtree 에 "hello" 들어간 파일)
- [ ] `#` → dirty 파일 리스트 (repo 안일 때)
- [ ] `@Foo` → 심볼 리스트
- [ ] ⌘F → palette 열림 + placeholder "Find files…"
- [ ] ESC → 닫힘

- [ ] **Step 8: 커밋**

```bash
git add apps/Sources/Views/Palette apps/Sources/ContentView.swift apps/Sources/CairnApp.swift apps/Sources/ViewModels/CommandPaletteModel.swift
git commit -m "feat(palette): add CommandPaletteView with 5 prefix modes"
```

---

## Task 16: 사이드바 확장 (Favorites auto + Home + AirDrop + Trash + Network + GitBranchFooter)

**Files:**
- Create: `apps/Sources/Views/Sidebar/SidebarAutoFavoriteRow.swift`
- Create: `apps/Sources/Views/Sidebar/GitBranchFooter.swift`
- Modify: `apps/Sources/Views/Sidebar/SidebarView.swift`

- [ ] **Step 1: `SidebarAutoFavoriteRow.swift`**

```swift
import SwiftUI
import AppKit

struct SidebarAutoFavoriteRow: View {
    let icon: String
    let label: String
    let url: URL
    let isSelected: Bool
    let onActivate: () -> Void

    var body: some View {
        SidebarItemRow(icon: icon, label: label, tint: nil, isSelected: isSelected)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
    }
}
```

- [ ] **Step 2: `GitBranchFooter.swift`**

```swift
import SwiftUI

struct GitBranchFooter: View {
    let branch: String
    let dirtyCount: Int

    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(theme.accent)
            Text(branch)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if dirtyCount > 0 {
                Text("• \(dirtyCount)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
    }
}
```

- [ ] **Step 3: `SidebarView.swift` 재구성**

```swift
struct SidebarView: View {
    @Bindable var app: AppModel
    @Bindable var scene: WindowSceneModel
    @Environment(\.cairnTheme) private var theme

    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var autoFavorites: [(icon: String, label: String, url: URL)] {
        [
            ("app.badge", "Applications", URL(fileURLWithPath: "/Applications")),
            ("menubar.dock.rectangle", "Desktop", home.appendingPathComponent("Desktop")),
            ("doc", "Documents", home.appendingPathComponent("Documents")),
            ("arrow.down.circle", "Downloads", home.appendingPathComponent("Downloads")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Favorites") {
                    ForEach(autoFavorites, id: \.url) { fav in
                        SidebarAutoFavoriteRow(
                            icon: fav.icon,
                            label: fav.label,
                            url: fav.url,
                            isSelected: isCurrent(fav.url),
                            onActivate: { scene.activeTab?.navigate(to: fav.url) }
                        )
                    }
                    ForEach(app.bookmarks.pinned) { entry in
                        pinnedRow(entry)
                    }
                }

                if !app.bookmarks.recent.isEmpty {
                    Section("Recent") {
                        ForEach(app.bookmarks.recent) { entry in
                            recentRow(entry)
                        }
                    }
                }

                Section("Cloud") {
                    if let iCloud = app.sidebar.iCloudURL {
                        row(url: iCloud, icon: "icloud", label: "iCloud Drive", tint: .blue, canPin: true)
                    }
                }

                Section("Locations") {
                    // Home
                    SidebarAutoFavoriteRow(
                        icon: "house",
                        label: NSUserName(),
                        url: home,
                        isSelected: isCurrent(home),
                        onActivate: { scene.activeTab?.navigate(to: home) }
                    )

                    ForEach(app.sidebar.locations, id: \.self) { loc in
                        row(url: loc,
                            icon: loc.path == "/" ? "desktopcomputer" : "externaldrive",
                            label: locationLabel(loc),
                            tint: nil,
                            canPin: true)
                    }

                    // AirDrop — NSSharingService with selection
                    SidebarItemRow(icon: "dot.radiowaves.up.forward", label: "AirDrop", tint: nil, isSelected: false)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let selected = scene.activeTab?.folder.selection ?? []
                            let urls = selected.map { URL(fileURLWithPath: $0) }
                            if urls.isEmpty {
                                NSSound.beep()  // TODO: toast "Select files first"
                            } else {
                                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
                            }
                        }

                    // Network
                    let network = URL(fileURLWithPath: "/Network")
                    row(url: network, icon: "network", label: "Network", tint: nil, canPin: false)

                    // Trash
                    let trash = home.appendingPathComponent(".Trash")
                    SidebarItemRow(icon: "trash", label: "Trash", tint: nil, isSelected: isCurrent(trash))
                        .contentShape(Rectangle())
                        .onTapGesture { scene.activeTab?.navigate(to: trash) }
                        .contextMenu {
                            Button("Empty Trash") {
                                let fm = FileManager.default
                                if let items = try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
                                    for u in items { try? fm.trashItem(at: u, resultingItemURL: nil) }
                                }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if let snap = scene.activeTab?.git?.snapshot, let branch = snap.branch {
                GitBranchFooter(branch: branch, dirtyCount: snap.dirtyCount)
            }
        }
        .background {
            ZStack {
                VisualEffectBlur(material: .sidebar)
                theme.sidebarTint.opacity(0.4)
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 200)
    }

    // 기존 helpers (pinnedRow, recentRow, row, locationLabel, isCurrent) —
    // `app.navigateUnscoped(to:)` → `scene.activeTab?.navigate(to:)` 로 교체.
}
```

- [ ] **Step 4: 빌드 + 테스트**

Expected: 51/51.

- [ ] **Step 5: E2E 수동**

- [ ] 사이드바에 Favorites 섹션 (4 개 기본 + 사용자 Pin)
- [ ] Locations 에 Home + Mac + AirDrop + Network + Trash 모두 보임
- [ ] Home (~) 클릭 → 홈 폴더로 이동
- [ ] Trash 클릭 → ~/.Trash 이동, 컨텍스트 "Empty Trash"
- [ ] Git repo 안 진입 시 사이드바 하단에 branch + dirty count

- [ ] **Step 6: 커밋**

```bash
git add apps/Sources/Views/Sidebar
git commit -m "feat(sidebar): Finder parity (Favorites auto + Home + AirDrop + Trash + Network) + Git footer"
```

---

## Task 17: File list Git 컬럼

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListView.swift`
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift`

- [ ] **Step 1: `FileListView.swift` 에 Git 컬럼 추가**

```swift
// NSUserInterfaceItemIdentifier extension
extension NSUserInterfaceItemIdentifier {
    // 기존
    static let git = NSUserInterfaceItemIdentifier("col.git")
}

// makeNSView 에서 조건부 컬럼 등록 (repo 안일 때만)
if tab.git?.snapshot != nil {
    let gitCol = NSTableColumn(identifier: .git)
    gitCol.title = "Git"
    gitCol.minWidth = 32
    gitCol.width = 48
    gitCol.sortDescriptorPrototype = NSSortDescriptor(key: "git", ascending: false)
    table.addTableColumn(gitCol)
}
```

실제로 FileListView 는 Tab 을 파라미터로 받아야 함 (git service 접근). 현재는 `folder: FolderModel` 받음 → `tab: Tab` 으로 확장, coordinator 도 tab 참조.

- [ ] **Step 2: Coordinator 에 git 셀 렌더링**

`tableView(_:viewFor:row:)` 의 switch 에 `.git` case 추가:

```swift
case .git:
    let path = entry.path.toString()
    let root = tab?.currentFolder?.path ?? ""
    let rel = path.hasPrefix(root) ? String(path.dropFirst(root.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) : path
    if let snap = tab?.git?.snapshot {
        let symbol: String
        let color: NSColor
        let relPath = URL(fileURLWithPath: rel)
        if snap.modified.contains(where: { $0.relativePath == rel }) { symbol = "M"; color = .systemYellow }
        else if snap.added.contains(where: { $0.relativePath == rel }) { symbol = "A"; color = .systemGreen }
        else if snap.deleted.contains(where: { $0.relativePath == rel }) { symbol = "D"; color = .systemRed }
        else if snap.untracked.contains(where: { $0.relativePath == rel }) { symbol = "??"; color = .secondaryLabelColor }
        else { symbol = "—"; color = .tertiaryLabelColor }
        cell.textField?.stringValue = symbol
        cell.textField?.textColor = color
    } else {
        cell.textField?.stringValue = "—"
        cell.textField?.textColor = .tertiaryLabelColor
    }
    cell.textField?.alignment = .center
```

> **주의**: FileListCoordinator 가 `tab` 을 참조하려면 생성자에 `tab: Tab` 추가. 기존 `folder: FolderModel` 는 `tab.folder` 로. SearchModel/PreviewModel 도 tab 경유.

- [ ] **Step 3: 빌드 + 테스트**

Expected: 51/51.

- [ ] **Step 4: E2E 수동**

- [ ] Git repo 폴더 열면 컬럼 보임
- [ ] 수정한 파일 → `M` (노랑)
- [ ] 추가한 파일 → `??` (회색) 또는 `A` (초록)
- [ ] Non-repo 폴더에서는 컬럼 없음

- [ ] **Step 5: 커밋**

```bash
git add apps/Sources/Views/FileList
git commit -m "feat(file-list): add Git status column (repo-aware)"
```

---

## Task 18: Ripgrep 번들링

**Files:**
- Add: `apps/Resources/rg` (universal binary, ~5MB)
- Modify: `apps/project.yml` (Copy Files build phase)
- Modify: `apps/Sources/CairnApp.swift` (런타임에 CAIRN_RG_PATH env 설정)

- [ ] **Step 1: `rg` 바이너리 획득**

Universal binary (arm64+x86_64). ripgrep release 에서 `ripgrep-*-x86_64-apple-darwin.tar.gz` 와 `ripgrep-*-aarch64-apple-darwin.tar.gz` 다운로드 후 `lipo -create -output apps/Resources/rg arm/rg x86/rg`.

또는 `brew install ripgrep` 한 뒤 `lipo -archs $(brew --prefix)/bin/rg` 로 확인, universal 이면 그대로 복사.

```bash
mkdir -p /Users/cyj/workspace/personal/cairn/apps/Resources
cp $(which rg) /Users/cyj/workspace/personal/cairn/apps/Resources/rg
lipo -info /Users/cyj/workspace/personal/cairn/apps/Resources/rg
# architectures must include x86_64 arm64
```

(만약 single-arch 면 ripgrep 공식 릴리스에서 두 바이너리 받아 lipo 로 합치기.)

- [ ] **Step 2: `project.yml` 에 리소스 포함**

`apps/project.yml` 의 Cairn 타겟 Resources 섹션에 추가:

```yaml
targets:
  Cairn:
    # ... 기존 ...
    sources:
      - path: Sources
    resources:
      - path: Resources/rg
```

`xcodegen generate` 후 생성된 Xcode project 에 Copy Bundle Resources phase 에 `rg` 포함 확인.

- [ ] **Step 3: 런타임에 rg 경로 세팅**

`CairnApp.init()` 또는 `WindowScene.init()` 에서:

```swift
init() {
    if let rgURL = Bundle.main.url(forResource: "rg", withExtension: nil) {
        setenv("CAIRN_RG_PATH", rgURL.path, 1)
    }
}
```

(Rust 쪽 `ffi_content_start` 이 `CAIRN_RG_PATH` env 를 읽음 — Task 8 에서 그렇게 구현.)

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
# 생성된 .app 안에 rg 있는지 확인:
find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" | head -1 | xargs -I {} ls {}/Contents/Resources/rg
```

Expected: `.app/Contents/Resources/rg` 존재, universal binary.

- [ ] **Step 5: E2E**

앱 실행 → ⌘K → `/hello world` 입력 → 번들된 rg 로 검색 결과 뜨는지 (시스템 $PATH rg 없어도 동작).

- [ ] **Step 6: 커밋**

```bash
git add apps/Resources/rg apps/project.yml apps/Sources/CairnApp.swift
git commit -m "feat(bundle): ship ripgrep binary in app Resources"
```

---

## Task 19: 로컬 CI + `phase-1-m1.8` + `v0.1.0-alpha.2` tag

**Files:** 없음 (검증 + tag)

- [ ] **Step 1: 전체 로컬 CI**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./scripts/build-rust.sh
./scripts/gen-bindings.sh
git status --short apps/Sources/Generated/
(cd apps && xcodegen generate)
(cd apps && xcodebuild -scheme Cairn -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | tail -5)
(cd apps && xcodebuild test -scheme CairnTests -destination "platform=macOS" \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | grep -E "Executed|TEST" | tail -5)
```

Expected:
- fmt / clippy / cargo test 전부 green (cairn-git 4 + cairn-index 12 + engine/ffi 기존)
- gen-bindings 후 Generated diff 있어도 이미 Task 8 에서 커밋된 상태라 이번엔 **diff 0**
- xcodebuild build PASS
- xcodebuild test **60+**

각 category 의 기대 테스트 수:
- M1.7 기존: 34
- Task 9 추가: +4 (Index + Git)
- Task 10 추가: +7 (Tab + Scene)
- Task 14 추가: +6 (Palette parse)
- Task 16/17 추가 (옵션): +0 (수동 E2E 위주)

합계 ~51. DoD 60+ 목표 미달 시 Task 9, 14 에 추가 케이스 보강 (content session / symbol 렌더링 snapshot 등).

> **DoD 조정**: 실제 landing 시점의 실제 테스트 수로 DoD 재조정. 목표는 "증가분 있으면 OK". 60+ 미달이면 spec §5 에 맞춰 몇 개 추가.

- [ ] **Step 2: E2E 체크리스트 (사용자 수행)**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1) && open "$APP"
```

Spec §10 DoD 체크:
- [ ] Glass Blue 실제로 파랗게 (다크/라이트 둘 다)
- [ ] Toolbar 에 back/forward/up + breadcrumb + ⌘K chip (나머지 버튼 없음)
- [ ] Tab bar, ⌘T/⌘W/⌘1-9/⌘⌥←→ 동작
- [ ] ⌘N 새 창
- [ ] ⌘K / ⌘F palette, 5 prefix (none / > / / / # / @) 전부 동작
- [ ] Content 결과 클릭 → 파일 열기 (line 스크롤 은 spec §3.5 에서 in-scope 였으나 PreviewModel.targetLine 확장 범위 고려해 이 plan 에서는 open-only, line 스크롤은 M2.x 로 descope — follow-up 섹션에 명시)
- [ ] Sidebar: Favorites 4개 + Home + AirDrop + Trash + Network 모두 렌더
- [ ] Git 컬럼 (repo 폴더만) + 사이드바 branch footer
- [ ] FSEvents: 외부 터미널에서 파일 추가·삭제 시 파일리스트 즉시 반영
- [ ] Ripgrep 번들 동작 (시스템 PATH rg 제거 후 테스트)

한 항목이라도 ❌ 면 STOP, 해당 sub-feature 를 M2.x 로 빼거나 fix.

- [ ] **Step 3: Tag**

```bash
cd /Users/cyj/workspace/personal/cairn
git tag phase-1-m1.8
git tag v0.1.0-alpha.2
git log --oneline phase-1-m1.7..phase-1-m1.8
```

Expected: Task 1–18 커밋 약 ~22 개 (일부 task 는 2 commit — index.rs build 커밋 별도 등).

- [ ] **Step 4: Tag 확인**

```bash
git tag -l | grep -E "^(phase|v0)" | sort
```

Expected:
```
phase-1-m1.1
phase-1-m1.2
phase-1-m1.3
phase-1-m1.4
phase-1-m1.5
phase-1-m1.6
phase-1-m1.7
phase-1-m1.8
v0.1.0-alpha
v0.1.0-alpha.1
v0.1.0-alpha.2
```

---

## 🎯 M1.8 Definition of Done

- [ ] `cairn-index` + `cairn-git` crates 구현 완료, `cargo test --workspace` green
- [ ] FFI bridge 확장, Generated regeneration 커밋됨
- [ ] `IndexService` / `GitService` Swift 래퍼 + tests
- [ ] `WindowSceneModel` + `Tab` — AppModel currentFolder 제거 후 tab-routing
- [ ] Glass Blue 실제로 blue (panelTint 파란 hue + sidebar material)
- [ ] Toolbar slim (pin/eye/reload/search field 제거), breadcrumb nav 옆
- [ ] TabBarView + 전체 키보드 단축키 (⌘T/W/1-9/⌥←→/N)
- [ ] CommandPaletteView + 5 prefix modes
- [ ] Sidebar Finder parity (Favorites auto 4 + Home + AirDrop + Trash + Network) + GitBranchFooter
- [ ] File list Git 컬럼
- [ ] Ripgrep 번들 + CAIRN_RG_PATH 런타임 세팅
- [ ] xcodebuild test 60+ (또는 실제 수로 재조정)
- [ ] FSEvents 실시간 반영 E2E 통과
- [ ] `git tag phase-1-m1.8` + `git tag v0.1.0-alpha.2`

---

## 이월된 follow-up (M2.x / Phase 3)

- Split pane (좌우 나란히)
- Pinned tabs + session restore
- macOS Finder Tags 통합
- Shared / Dropbox·GDrive 감지
- Light mode CairnTheme variant
- Git: staged/worktree 분리, diff viewer, commit history
- Smart folders
- 심볼 grammar 추가 (Go/Kotlin/Ruby 등)
- Content 결과 inline replace
- Drag & drop 파일 이동
- Palette `⌘⏎` 보조 액션 (Reveal, Copy Path, Open With)
- Content 결과 클릭 시 preview pane 에서 line 스크롤 (PreviewModel.targetLine 확장)

---

## 다음 마일스톤 (M2.1+)

M1.8 완료 후:
- Drag & drop 구현
- Preview pane 강화 (line routing, 이미지 화면 맞춤, 비디오 썸네일)
- `⌘⏎` palette 보조 액션
- Pinned tabs + session restore
- macOS Tags 통합

Phase 3 는 Theme Switcher + Light mode variants + Split pane.
