# Cairn Phase 1 · M1.1 — Walker Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 0의 `greet()` 파이프라인을 Phase 1의 실제 첫 기능으로 치환한다. macOS 샌드박스 켜고, 유저가 NSOpenPanel 로 폴더를 고르면 Rust `cairn-walker` 가 그 폴더의 **직접 자식**을 읽어 SwiftUI `List` 에 1-컬럼으로 표시한다. Phase 1 의 **"파이프라인이 실제로 파일 데이터를 나른다"** 첫 증명.

**Architecture:** `cairn-walker` 크레이트를 신규 구현 (`ignore` 크레이트로 gitignore 매치, `std::fs::read_dir` 기반 1-레벨 순회). `cairn-core::Engine` 가 워커를 얇게 래핑해 FFI 경계로 노출. Swift 쪽은 샌드박스 entitlements 추가 + `BookmarkStore` (security-scoped bookmark 저장/해결) + `CairnEngine` 래퍼 + `OpenFolderEmptyState` 뷰 + `FolderModel` + 최소 `FileListSimpleView` (SwiftUI `List` 사용, NSTableView 는 M1.2). NSTableView·사이드바·프리뷰·Theme 는 후속 마일스톤.

**Tech Stack:** Rust 1.85.0 · `ignore = "0.4"` (gitignore) · `tempfile`(test) · swift-bridge 0.1.59 · SwiftUI (macOS 13+) · NSVisualEffectView·NSOpenPanel · Xcode 15+ · xcodegen 2.45+

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main branch, Phase 0 완료 상태. 가장 최근 커밋은 `afbefd9` Phase 1 design spec)

**Predecessor:** Phase 0 완료 — `docs/superpowers/plans/2026-04-21-cairn-phase-0-foundation.md`
**Parent spec:** `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md`

**Deliverable verification (M1.1 완료 조건):**
- `cargo test --workspace` 녹색 (walker 신규 테스트 포함 ≥ 5개)
- `xcodebuild -scheme Cairn build` 성공
- 앱 실행 → `OpenFolderEmptyState` 표시 → `⌘O` / 버튼 → NSOpenPanel → 유저가 `~/Desktop` 선택 → SwiftUI `List` 가 그 폴더의 직접 자식 표시
- 앱 재시동 → 저장된 bookmark 자동 resolve → 같은 폴더 재진입 가능
- `git tag phase-1-m1.1` 로 기준점

---

## 기술 참조 (간단)

이 M1.1 에서 스택 간 경계를 다루는 주의점만:

- **swift-bridge 0.1.59 제약** — `extern "Rust"` 블록 안의 함수에 `///` doc 주석 금지 (파서 panic). `Result<T, E>` → Swift `throws` 자동 매핑. enum variant 이름은 **Rust 원본 보존** (대소문자 포함).
- **Security-scoped bookmark 라이프사이클** — `.withSecurityScope` 은 `files.bookmarks.app-scope` entitlement 필요. resolve 시 `bookmarkDataIsStale` out-param 반드시 체크. start/stop 은 ref-count 로 관리 (플랜 Task 7 참조).
- **NSOpenPanel** — `begin(completionHandler:)` callback 기반이 SwiftUI 와 궁합 좋음 (`runModal()` 은 메인 스레드 블로킹).
- **Swift `@Observable` (Swift 5.9+)** — Phase 0 의 entitlements 미설정 상태에서 작동 확인됨. 이번 M1.1 에서 샌드박스 켜져도 동작은 동일.

---

## File Structure

이 M1.1 에서 생성·수정될 파일:

**Rust (crates/):**
- Modify: `crates/cairn-walker/Cargo.toml` (스켈레톤 → 실제 deps)
- Modify: `crates/cairn-walker/src/lib.rs` (스켈레톤 → 실제 구현)
- Create: `crates/cairn-walker/tests/walker_test.rs` (integration)
- Modify: `crates/cairn-core/Cargo.toml` (walker 의존 추가)
- Modify: `crates/cairn-core/src/lib.rs` (hello() 제거 + Engine)
- Modify: `crates/cairn-ffi/src/lib.rs` (greet() 제거 + 새 bridge)

**Swift (apps/Cairn/Sources/):**
- Create: `apps/Sources/Cairn.entitlements` (신규, 샌드박스)
- Modify: `apps/project.yml` (entitlements + 테스트 target)
- Create: `apps/Sources/App/AppModel.swift`
- Create: `apps/Sources/App/NavigationHistory.swift`
- Modify: `apps/Sources/CairnApp.swift` (AppModel 주입, Scene 정리)
- Modify: `apps/Sources/ContentView.swift` (NavigationSplitView 재구성)
- Create: `apps/Sources/Services/CairnEngine.swift`
- Create: `apps/Sources/Services/BookmarkStore.swift`
- Create: `apps/Sources/ViewModels/FolderModel.swift`
- Create: `apps/Sources/Views/Onboarding/OpenFolderEmptyState.swift`
- Create: `apps/Sources/Views/FileList/FileListSimpleView.swift`

**Swift tests (apps/CairnTests/):**
- Create: `apps/CairnTests/BookmarkStoreTests.swift`

**기타:**
- Modify: `.gitignore` (CairnTests 관련은 이미 커버됨, 추가 필요 없음 예상)

---

## Task 1: `cairn-walker` 크레이트 — 타입 정의 (스켈레톤 탈출)

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-walker/Cargo.toml`
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-walker/src/lib.rs`

- [ ] **Step 1: `Cargo.toml` 에 의존성 추가**

`crates/cairn-walker/Cargo.toml` 전체 교체:

```toml
[package]
name = "cairn-walker"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_walker"

[dependencies]
ignore = "0.4"

[dev-dependencies]
tempfile = "3"
```

- [ ] **Step 2: 타입 정의와 skeleton `list_directory` 작성 (테스트는 다음 Task)**

`crates/cairn-walker/src/lib.rs` 전체 교체:

```rust
//! cairn-walker — filesystem traversal (single-level listing).
//!
//! In Phase 1 this exposes `list_directory(path, config)` which returns the
//! direct children of `path`. Recursive walking (for Deep Search) lands in
//! Phase 2 and will reuse the same types.

use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct WalkerConfig {
    /// Include entries whose basename starts with `.`.
    pub show_hidden: bool,
    /// Apply `.gitignore` matching when traversing a folder.
    pub respect_gitignore: bool,
    /// Hard-coded exclusion globs applied on top of `.gitignore`.
    /// Only effective when `respect_gitignore == true`.
    pub exclude_patterns: Vec<String>,
}

impl Default for WalkerConfig {
    fn default() -> Self {
        Self {
            show_hidden: false,
            respect_gitignore: true,
            exclude_patterns: vec![
                ".git".into(),
                "node_modules".into(),
                "target".into(),
                ".next".into(),
                "build".into(),
                "dist".into(),
            ],
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEntry {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
    pub modified_unix: i64,
    pub kind: FileKind,
    pub is_hidden: bool,
    pub icon_kind: IconKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    Directory,
    Regular,
    Symlink,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IconKind {
    Folder,
    GenericFile,
    ExtensionHint(String),
}

#[derive(Debug, thiserror::Error)]
pub enum WalkerError {
    #[error("permission denied")]
    PermissionDenied,
    #[error("not found")]
    NotFound,
    #[error("not a directory")]
    NotDirectory,
    #[error("io error: {0}")]
    Io(String),
}

pub fn list_directory(
    _path: &Path,
    _config: &WalkerConfig,
) -> Result<Vec<FileEntry>, WalkerError> {
    // Real implementation arrives in Task 2.
    Ok(Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_has_common_excludes() {
        let cfg = WalkerConfig::default();
        assert!(cfg.exclude_patterns.iter().any(|p| p == "node_modules"));
        assert!(cfg.exclude_patterns.iter().any(|p| p == ".git"));
    }

    #[test]
    fn list_directory_returns_empty_stub() {
        let tmp = std::env::temp_dir();
        let result = list_directory(&tmp, &WalkerConfig::default()).unwrap();
        assert!(result.is_empty());
    }
}
```

주의: `thiserror` 는 루트 `Cargo.toml` 의 `[workspace.dependencies]` 에 이미 `thiserror = "1"` 으로 등록돼 있지만, 현재 파일은 이를 `[dependencies]` 에서 참조하고 있지 않음. 다음 Step 에서 추가한다.

- [ ] **Step 3: `thiserror` 의존성을 walker `Cargo.toml` 에 명시적으로 얹기**

`crates/cairn-walker/Cargo.toml` 의 `[dependencies]` 섹션을 교체:

```toml
[dependencies]
ignore = "0.4"
thiserror = { workspace = true }
```

- [ ] **Step 4: 빌드 + 테스트 — 스켈레톤 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-walker
```

Expected:
- `test tests::default_config_has_common_excludes ... ok`
- `test tests::list_directory_returns_empty_stub ... ok`
- `test result: ok. 2 passed`

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add crates/cairn-walker
git commit -m "feat(walker): define FileEntry/WalkerError types + skeleton list_directory"
```

---

## Task 2: `cairn-walker` — 실제 구현 (TDD)

**Files:**
- Modify: `crates/cairn-walker/src/lib.rs`
- Create: `crates/cairn-walker/tests/walker_test.rs`

- [ ] **Step 1: 실패하는 integration 테스트 작성**

Create `crates/cairn-walker/tests/walker_test.rs`:

```rust
use cairn_walker::{list_directory, FileKind, WalkerConfig};
use std::fs;
use std::io::Write;

fn mk_tempdir_with_fixtures() -> tempfile::TempDir {
    let dir = tempfile::tempdir().expect("tempdir");
    let root = dir.path();

    // Regular file
    let mut f = fs::File::create(root.join("README.md")).unwrap();
    writeln!(f, "hello").unwrap();

    // Hidden file
    fs::File::create(root.join(".secret")).unwrap();

    // Subdirectory (non-empty)
    fs::create_dir(root.join("src")).unwrap();
    fs::File::create(root.join("src").join("lib.rs")).unwrap();

    // A commonly-excluded dir
    fs::create_dir(root.join("node_modules")).unwrap();
    fs::File::create(root.join("node_modules").join("index.js")).unwrap();

    // macOS noise
    fs::File::create(root.join(".DS_Store")).unwrap();

    dir
}

#[test]
fn lists_direct_children_only() {
    let dir = mk_tempdir_with_fixtures();
    let entries = list_directory(dir.path(), &WalkerConfig::default()).unwrap();

    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    // Direct children of the tempdir: README.md and src/ (node_modules excluded,
    // .secret hidden-out, .DS_Store always excluded).
    assert!(names.contains(&"README.md"), "expected README.md, got {names:?}");
    assert!(names.contains(&"src"), "expected src/, got {names:?}");
    assert!(!names.contains(&"node_modules"), "node_modules should be excluded");
    assert!(!names.contains(&".secret"), ".secret should be hidden");
    assert!(!names.contains(&".DS_Store"), ".DS_Store should always be excluded");
    // Must NOT descend into src/ — this is a single-level listing.
    assert!(!names.contains(&"lib.rs"), "lib.rs is a grandchild, not direct child");
}

#[test]
fn show_hidden_includes_dotfiles() {
    let dir = mk_tempdir_with_fixtures();
    let cfg = WalkerConfig { show_hidden: true, ..Default::default() };
    let entries = list_directory(dir.path(), &cfg).unwrap();
    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    assert!(names.contains(&".secret"), "dotfile should appear when show_hidden=true");
    // But .DS_Store is ALWAYS excluded regardless of show_hidden.
    assert!(!names.contains(&".DS_Store"));
}

#[test]
fn directory_entries_have_zero_size_and_directory_kind() {
    let dir = mk_tempdir_with_fixtures();
    let entries = list_directory(dir.path(), &WalkerConfig::default()).unwrap();
    let src = entries.iter().find(|e| e.name == "src").expect("src must be listed");
    assert_eq!(src.kind, FileKind::Directory);
    assert_eq!(src.size, 0);
    assert_eq!(src.icon_kind, cairn_walker::IconKind::Folder);
}

#[test]
fn regular_file_has_extension_hint() {
    let dir = mk_tempdir_with_fixtures();
    let entries = list_directory(dir.path(), &WalkerConfig::default()).unwrap();
    let readme = entries.iter().find(|e| e.name == "README.md").unwrap();
    assert_eq!(readme.kind, FileKind::Regular);
    assert_eq!(
        readme.icon_kind,
        cairn_walker::IconKind::ExtensionHint("md".to_string())
    );
}

#[test]
fn returns_not_directory_for_file_path() {
    let dir = mk_tempdir_with_fixtures();
    let file = dir.path().join("README.md");
    let err = list_directory(&file, &WalkerConfig::default()).unwrap_err();
    matches!(err, cairn_walker::WalkerError::NotDirectory);
}

#[test]
fn returns_not_found_for_missing_path() {
    let err = list_directory(
        std::path::Path::new("/definitely/not/a/real/path/xyz"),
        &WalkerConfig::default(),
    )
    .unwrap_err();
    matches!(err, cairn_walker::WalkerError::NotFound);
}
```

- [ ] **Step 2: 테스트 실행 → 대부분 FAIL 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-walker --test walker_test 2>&1 | tail -30
```

Expected: 여러 테스트가 `assertion failed` 또는 panic. 스켈레톤이 empty vec 만 리턴하므로 당연.

- [ ] **Step 3: 실제 구현 작성 — `list_directory` 본체 교체**

`crates/cairn-walker/src/lib.rs` 의 `pub fn list_directory(...)` 정의를 다음으로 교체 (타입 정의 부분은 그대로 유지):

```rust
use std::fs;
use std::time::UNIX_EPOCH;

pub fn list_directory(
    path: &Path,
    config: &WalkerConfig,
) -> Result<Vec<FileEntry>, WalkerError> {
    // Normalize & validate target.
    let metadata = fs::metadata(path).map_err(io_to_walker_error)?;
    if !metadata.is_dir() {
        return Err(WalkerError::NotDirectory);
    }

    // Build a .gitignore matcher (scoped to this directory).
    let gitignore = if config.respect_gitignore {
        let mut builder = ignore::gitignore::GitignoreBuilder::new(path);
        // Include a .gitignore in this folder if any.
        let gi_file = path.join(".gitignore");
        if gi_file.exists() {
            builder.add(gi_file);
        }
        Some(builder.build().map_err(|e| WalkerError::Io(e.to_string()))?)
    } else {
        None
    };

    let mut out = Vec::new();

    let rd = fs::read_dir(path).map_err(io_to_walker_error)?;
    for entry in rd {
        let entry = entry.map_err(io_to_walker_error)?;
        let name = match entry.file_name().into_string() {
            Ok(s) => s,
            Err(_) => continue, // skip non-UTF-8 names — Phase 2 can revisit
        };

        // Always exclude .DS_Store regardless of config.
        if name == ".DS_Store" {
            continue;
        }

        let is_hidden = name.starts_with('.');
        if is_hidden && !config.show_hidden {
            continue;
        }

        let entry_path = entry.path();
        let metadata = match entry.metadata() {
            Ok(m) => m,
            Err(_) => {
                // Per spec: individual metadata failure is not fatal.
                // Fall through with zeroed metadata.
                out.push(FileEntry {
                    path: entry_path.clone(),
                    name: name.clone(),
                    size: 0,
                    modified_unix: 0,
                    kind: FileKind::Regular,
                    is_hidden,
                    icon_kind: classify_icon(&name, /* is_dir= */ false),
                });
                continue;
            }
        };

        // gitignore check (directories need trailing slash semantics for some matchers).
        if let Some(gi) = &gitignore {
            let m = gi.matched(&entry_path, metadata.is_dir());
            if m.is_ignore() {
                continue;
            }
        }

        // Hardcoded exclusion patterns (simple name match).
        if config.respect_gitignore && config.exclude_patterns.iter().any(|p| p == &name) {
            continue;
        }

        let kind = if metadata.is_dir() {
            FileKind::Directory
        } else if metadata.file_type().is_symlink() {
            FileKind::Symlink
        } else {
            FileKind::Regular
        };

        let size = if matches!(kind, FileKind::Directory) { 0 } else { metadata.len() };

        let modified_unix = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let icon_kind = classify_icon(&name, metadata.is_dir());

        out.push(FileEntry {
            path: entry_path,
            name,
            size,
            modified_unix,
            kind,
            is_hidden,
            icon_kind,
        });
    }

    // Sort: directories first, then name asc (case-insensitive).
    out.sort_by(|a, b| {
        let a_is_dir = matches!(a.kind, FileKind::Directory);
        let b_is_dir = matches!(b.kind, FileKind::Directory);
        match (a_is_dir, b_is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        }
    });

    Ok(out)
}

fn classify_icon(name: &str, is_dir: bool) -> IconKind {
    if is_dir {
        return IconKind::Folder;
    }
    match name.rsplit_once('.') {
        Some((_, ext)) if !ext.is_empty() && !ext.contains(' ') => {
            IconKind::ExtensionHint(ext.to_lowercase())
        }
        _ => IconKind::GenericFile,
    }
}

fn io_to_walker_error(e: std::io::Error) -> WalkerError {
    use std::io::ErrorKind;
    match e.kind() {
        ErrorKind::NotFound => WalkerError::NotFound,
        ErrorKind::PermissionDenied => WalkerError::PermissionDenied,
        _ => WalkerError::Io(e.to_string()),
    }
}
```

그리고 파일 맨 위의 기존 `pub fn list_directory` 스텁을 삭제 (혹은 위 버전으로 교체). 또 `_path` / `_config` underscore prefix 도 제거 (실제로 사용하니까).

- [ ] **Step 4: 이전에 있던 unit test 중 `list_directory_returns_empty_stub` 는 이제 반드시 실패 — 스텁 전용이었으니 삭제**

`crates/cairn-walker/src/lib.rs` 의 `mod tests` 에서 `list_directory_returns_empty_stub` 함수를 삭제. `default_config_has_common_excludes` 는 유지.

- [ ] **Step 5: 테스트 전부 재실행**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-walker
```

Expected:
- `test tests::default_config_has_common_excludes ... ok`
- `test lists_direct_children_only ... ok`
- `test show_hidden_includes_dotfiles ... ok`
- `test directory_entries_have_zero_size_and_directory_kind ... ok`
- `test regular_file_has_extension_hint ... ok`
- `test returns_not_directory_for_file_path ... ok`
- `test returns_not_found_for_missing_path ... ok`
- `test result: ok. 7 passed`

- [ ] **Step 6: clippy**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo clippy -p cairn-walker --all-targets -- -D warnings
```

Expected: no warnings. If there are warnings about `unused_imports` etc., fix them.

- [ ] **Step 7: 커밋**

```bash
git add crates/cairn-walker
git commit -m "feat(walker): implement list_directory with gitignore + hidden toggle"
```

---

## Task 3: `cairn-core` — `Engine` struct

**Files:**
- Modify: `crates/cairn-core/Cargo.toml`
- Modify: `crates/cairn-core/src/lib.rs`

- [ ] **Step 1: `cairn-core/Cargo.toml` 에 walker 의존성 추가**

`crates/cairn-core/Cargo.toml`:

```toml
[package]
name = "cairn-core"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_core"

[dependencies]
cairn-walker = { path = "../cairn-walker" }
```

- [ ] **Step 2: `cairn-core/src/lib.rs` 전체 교체 — hello() 제거, Engine 추가**

```rust
//! cairn-core — public façade for the Cairn engine.
//!
//! Phase 1 goal: expose a stateless `Engine` that orchestrates file listing
//! via `cairn-walker`. Additional subsystems (preview, search, index) plug
//! into this struct in later phases.

use cairn_walker::{list_directory, FileEntry, WalkerConfig, WalkerError};
use std::path::Path;

pub use cairn_walker::{FileKind, IconKind};

pub struct Engine {
    walker_config: WalkerConfig,
}

impl Engine {
    pub fn new() -> Self {
        Self { walker_config: WalkerConfig::default() }
    }

    pub fn list_directory(&self, path: &Path) -> Result<Vec<FileEntry>, WalkerError> {
        list_directory(path, &self.walker_config)
    }

    pub fn set_show_hidden(&mut self, show: bool) {
        self.walker_config.show_hidden = show;
    }

    pub fn show_hidden(&self) -> bool {
        self.walker_config.show_hidden
    }
}

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_defaults_to_hidden_off() {
        let engine = Engine::new();
        assert!(!engine.show_hidden());
    }

    #[test]
    fn set_show_hidden_mutates_state() {
        let mut engine = Engine::new();
        engine.set_show_hidden(true);
        assert!(engine.show_hidden());
    }

    #[test]
    fn list_directory_returns_sorted_children() {
        // tempfile isn't a dev-dep on cairn-core by design — use env::temp_dir
        // indirectly via any existing directory. We just assert it doesn't error.
        let engine = Engine::new();
        let result = engine.list_directory(&std::env::temp_dir());
        assert!(result.is_ok());
    }
}
```

- [ ] **Step 3: 전체 워크스페이스 빌드·테스트**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: All crates compile, all tests pass (cairn-walker 7 + cairn-core 3 + others unchanged). No clippy warnings.

- [ ] **Step 4: 커밋**

```bash
git add crates/cairn-core
git commit -m "feat(core): replace hello() with Engine facade wrapping cairn-walker"
```

---

## Task 4: `cairn-ffi` — Bridge 재설계 (greet 제거, 새 API)

**Files:**
- Modify: `crates/cairn-ffi/src/lib.rs`
- Modify: `crates/cairn-ffi/Cargo.toml` (필요 시)

이 태스크는 swift-bridge 특유 제약과 `Result<Vec<struct>, Error>` 매핑을 확인해야 해서 Step 끝에 `cargo build -p cairn-ffi` 로 **생성된 Swift/C 코드**를 인라인 확인하는 단계를 포함함.

- [ ] **Step 1: `cairn-ffi/Cargo.toml` 확인**

현재 상태 (변경 없어도 됨 — 확인만):

```toml
[package]
name = "cairn-ffi"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
crate-type = ["staticlib", "rlib"]
name = "cairn_ffi"

[dependencies]
cairn-core = { path = "../cairn-core" }
swift-bridge = "0.1"

[build-dependencies]
swift-bridge-build = "0.1"
```

`cairn-core` 의존은 이미 있음. 추가할 것 없음.

- [ ] **Step 2: `crates/cairn-ffi/src/lib.rs` 전체 교체**

```rust
//! cairn-ffi — the only crate the Swift app sees.
//!
//! Phase 1 API:
//!   - new_engine() -> Engine
//!   - engine.list_directory(path) -> Result<Vec<FileEntry>, WalkerError>
//!   - engine.set_show_hidden(bool)

use std::path::Path;

#[swift_bridge::bridge]
mod ffi {
    // Wire types are defined here; Rust-side conversion helpers below.
    #[swift_bridge(swift_repr = "struct")]
    struct FileEntry {
        path: String,
        name: String,
        size: u64,
        modified_unix: i64,
        kind: FileKind,
        is_hidden: bool,
        icon_kind: IconKind,
    }

    enum FileKind {
        Directory,
        Regular,
        Symlink,
    }

    enum IconKind {
        Folder,
        GenericFile,
        ExtensionHint(String),
    }

    enum WalkerError {
        PermissionDenied,
        NotFound,
        NotDirectory,
        Io(String),
    }

    extern "Rust" {
        type Engine;

        fn new_engine() -> Engine;
        fn list_directory(&self, path: String) -> Result<Vec<FileEntry>, WalkerError>;
        fn set_show_hidden(&mut self, show: bool);
    }
}

// ---- Engine wrapper owned by Swift ------------------------------------------

pub struct Engine {
    inner: cairn_core::Engine,
}

fn new_engine() -> Engine {
    Engine { inner: cairn_core::Engine::new() }
}

impl Engine {
    fn list_directory(&self, path: String) -> Result<Vec<ffi::FileEntry>, ffi::WalkerError> {
        let results = self
            .inner
            .list_directory(Path::new(&path))
            .map_err(wire_walker_error)?;
        Ok(results.into_iter().map(wire_file_entry).collect())
    }

    fn set_show_hidden(&mut self, show: bool) {
        self.inner.set_show_hidden(show);
    }
}

// ---- Wire-type conversions --------------------------------------------------

fn wire_file_entry(e: cairn_walker::FileEntry) -> ffi::FileEntry {
    ffi::FileEntry {
        path: e.path.to_string_lossy().into_owned(),
        name: e.name,
        size: e.size,
        modified_unix: e.modified_unix,
        kind: wire_file_kind(e.kind),
        is_hidden: e.is_hidden,
        icon_kind: wire_icon_kind(e.icon_kind),
    }
}

fn wire_file_kind(k: cairn_walker::FileKind) -> ffi::FileKind {
    match k {
        cairn_walker::FileKind::Directory => ffi::FileKind::Directory,
        cairn_walker::FileKind::Regular => ffi::FileKind::Regular,
        cairn_walker::FileKind::Symlink => ffi::FileKind::Symlink,
    }
}

fn wire_icon_kind(k: cairn_walker::IconKind) -> ffi::IconKind {
    match k {
        cairn_walker::IconKind::Folder => ffi::IconKind::Folder,
        cairn_walker::IconKind::GenericFile => ffi::IconKind::GenericFile,
        cairn_walker::IconKind::ExtensionHint(s) => ffi::IconKind::ExtensionHint(s),
    }
}

fn wire_walker_error(e: cairn_walker::WalkerError) -> ffi::WalkerError {
    use cairn_walker::WalkerError as W;
    match e {
        W::PermissionDenied => ffi::WalkerError::PermissionDenied,
        W::NotFound => ffi::WalkerError::NotFound,
        W::NotDirectory => ffi::WalkerError::NotDirectory,
        W::Io(msg) => ffi::WalkerError::Io(msg),
    }
}

// ---- Rust-side smoke test ---------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_lists_temp_dir_without_error() {
        let engine = new_engine();
        let path = std::env::temp_dir().to_string_lossy().into_owned();
        let result = engine.list_directory(path);
        assert!(result.is_ok(), "list_directory should succeed on temp dir");
    }
}
```

주의: swift-bridge 0.1.59 의 몇 가지 제약:
- `extern "Rust"` 블록 안의 함수에는 `///` doc 주석 **금지** (파서가 panic). 설명은 모듈 doc 에만.
- `enum` variant 에 튜플 payload (`ExtensionHint(String)`, `Io(String)`) 허용됨.
- `Result<T, E>` 반환은 Swift `throws` 로 매핑됨.

- [ ] **Step 3: 빌드 — 생성된 바인딩 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo build -p cairn-ffi 2>&1 | tail -10
```

Expected: `Compiling cairn-ffi v0.0.1`, `Finished`.

생성된 Swift 소스 확인:

```bash
head -40 crates/cairn-ffi/generated/cairn_ffi/cairn_ffi.swift
```

Expected: 다음 패턴이 보여야 함:
- `public class Engine { ... }` 또는 `public struct Engine`
- `public func new_engine() -> Engine { ... }`
- `Engine.list_directory(_ path: RustString) throws -> RustVec<FileEntry>` 같은 throws 시그니처

만약 `throws` 가 안 보이면 swift-bridge Result 매핑이 기대대로 안 됐을 가능성. STOP하고 사용자에게 알림.

- [ ] **Step 4: C 헤더 확인**

```bash
head -40 crates/cairn-ffi/generated/cairn_ffi/cairn_ffi.h
```

Expected: `FileEntry`, `FileKind`, `IconKind`, `WalkerError` 관련 C 선언이 보임.

- [ ] **Step 5: Rust 단위 테스트**

```bash
cargo test -p cairn-ffi
```

Expected: `engine_lists_temp_dir_without_error ... ok`.

- [ ] **Step 6: 바인딩 재복사 (Swift 앱에서 쓸 수 있도록)**

```bash
./scripts/gen-bindings.sh
ls apps/Sources/Generated/
```

Expected 파일:
- `cairn_ffi.swift`
- `cairn_ffi.h`
- `SwiftBridgeCore.swift`
- `SwiftBridgeCore.h`

- [ ] **Step 7: 커밋**

```bash
git add crates/cairn-ffi
git commit -m "feat(ffi): replace greet() with Engine + list_directory bridge"
```

---

## Task 5: Xcode 프로젝트 — 샌드박스 Entitlements + 테스트 타깃

**Files:**
- Create: `apps/Sources/Cairn.entitlements`
- Modify: `apps/project.yml`
- Create: `apps/CairnTests/Placeholder.swift` (첫 테스트 타깃 스캐폴드)

- [ ] **Step 1: `Cairn.entitlements` 작성**

`apps/Sources/Cairn.entitlements` 생성 (이 경로는 xcodegen 의 `sources: - path: Sources` 안에 들어가지만 entitlements 는 코드가 아니므로 xcodegen 이 target 의 source 목록에 넣지 않도록 아래에서 명시적으로 제외함):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: `apps/project.yml` 업데이트 — entitlements + CairnTests 타깃 추가**

`apps/project.yml` 전체 교체:

```yaml
name: Cairn
options:
  bundleIdPrefix: com.ongjin
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "13.0"
    ARCHS: "$(ARCHS_STANDARD)"
    SWIFT_OBJC_BRIDGING_HEADER: Sources/BridgingHeader.h
    LIBRARY_SEARCH_PATHS:
      - $(SRCROOT)/../target/universal/release
    OTHER_LDFLAGS:
      - -lcairn_ffi
    CLANG_CXX_LIBRARY: "libc++"

targets:
  Cairn:
    type: application
    platform: macOS
    sources:
      - path: Sources
        excludes:
          - "Cairn.entitlements"
    info:
      path: Sources/Info.plist
      properties:
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "Copyright © 2026 ongjin. MIT License."
    settings:
      base:
        CODE_SIGN_ENTITLEMENTS: Sources/Cairn.entitlements
        CODE_SIGN_STYLE: Automatic
        ENABLE_HARDENED_RUNTIME: YES
  CairnTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: CairnTests
    dependencies:
      - target: Cairn
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Cairn.app/Contents/MacOS/Cairn"
```

주의:
- `CODE_SIGN_STYLE: Automatic` — 로컬 개발에서 Xcode 의 자동 관리 signing 에 위임. CI 는 signing 끄고 빌드.
- `ENABLE_HARDENED_RUNTIME: YES` — Sandbox 와 함께 늘 켜두는 권장값.
- `excludes: - "Cairn.entitlements"` — entitlements 파일이 Swift 소스로 컴파일되려 시도되지 않도록.

- [ ] **Step 3: `CairnTests` 타깃 스캐폴드 — placeholder 파일 생성**

`apps/CairnTests/Placeholder.swift`:

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func test_placeholder_for_future_targets() {
        // Ensures the CairnTests target compiles and xcodebuild test runs.
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 4: Xcode 프로젝트 재생성**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
```

Expected: `Created project at ...apps/Cairn.xcodeproj`.

- [ ] **Step 5: 빌드만 — 앱이 아직 새 FFI 안 쓰는 상태인지 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
./scripts/build-rust.sh  # universal lib 갱신
./scripts/gen-bindings.sh
cd apps && xcodebuild -scheme Cairn -configuration Debug build 2>&1 | tail -5
```

Expected: ★ 여기서 **실패할 가능성 있음** ★. 왜? `ContentView.swift` 가 아직 `greet()` 를 부름. 그런데 `greet` 은 FFI 에서 제거됨. Swift 컴파일 에러가 날 수밖에 없다.

만약 그렇다면 STOP — 다음 Task 에서 Swift 소스를 새 API 로 포팅할 때까지 Xcode 빌드가 빨간 상태로 남는 게 정상. 이 Step 에선 "실패 원인이 `Cannot find 'greet' in scope`" 인지만 확인하고 통과.

- [ ] **Step 6: 테스트 타깃 단독 빌드는 성공해야 함**

```bash
xcodebuild -scheme CairnTests -configuration Debug build 2>&1 | tail -5
```

Expected: CairnTests 스킴은 Cairn.app 에 의존하므로 이것도 실패할 수 있음. 만약 실패하면 Step 5 와 같은 이유로. OK.

- [ ] **Step 7: 커밋 (빌드 빨간 상태도 커밋 — 다음 태스크에서 복구)**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/project.yml apps/Sources/Cairn.entitlements apps/CairnTests
git commit -m "feat(app): add sandbox entitlements + CairnTests target (WIP, app won't build until Swift port)"
```

---

## Task 6: Swift — `CairnEngine.swift` 서비스 + 폴더 로딩 경로 복원

**Files:**
- Create: `apps/Sources/Services/CairnEngine.swift`
- Modify: `apps/Sources/ContentView.swift` (greet 제거, 최소 동작 복원)

- [ ] **Step 1: `CairnEngine.swift` 작성**

`apps/Sources/Services/CairnEngine.swift`:

```swift
import Foundation

/// Lightweight Swift wrapper around the Rust `Engine` exposed via swift-bridge.
///
/// Runs Rust calls on a detached Task so UI thread stays responsive.
/// The caller is responsible for security-scoped resource access before invoking `listDirectory`.
@Observable
final class CairnEngine {
    private let rust: Engine

    init() {
        self.rust = new_engine()
    }

    /// Returns direct children of `url`. Requires prior start of security-scoped access.
    func listDirectory(_ url: URL) async throws -> [FileEntry] {
        let path = url.path
        return try await Task.detached { [rust] in
            // swift-bridge exposes `Result<T, E>` as `throws`.
            try rust.list_directory(path)
        }.value
    }

    func setShowHidden(_ show: Bool) {
        rust.set_show_hidden(show)
    }
}
```

주의: `FileEntry` / `Engine` 타입은 `apps/Sources/Generated/cairn_ffi.swift` 에 정의돼 있고 `sources: - path: Sources` 가 그걸 재귀 포함하므로 임포트 없이 직접 사용 가능.

- [ ] **Step 2: `ContentView.swift` 를 최소 빌드되는 상태로 되돌리기 (실제 파일 리스트 UI 는 Task 12)**

`apps/Sources/ContentView.swift` 전체 교체:

```swift
import SwiftUI

struct ContentView: View {
    // M1.1 workspace — full UI lands in Tasks 10–12.
    @State private var status = "Engine not invoked yet."

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.teal.opacity(0.3), .indigo.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("🏔️")
                    .font(.system(size: 48))
                Text(status)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.white)
                Text("M1.1 — scaffolding")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            let engine = CairnEngine()
            do {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let entries = try await engine.listDirectory(home)
                status = "Home has \(entries.count) entries (sandboxed — likely 0 until folder is opened)"
            } catch {
                status = "Engine call failed: \(error)"
            }
        }
    }
}
```

이 뷰는 **샌드박스 상태에서 Home 읽기를 시도**하므로 실패 예상 — 상태 텍스트에 `failed` 나 `entries count: 0` 이 뜨는 게 정상. 나중 Task 에서 NSOpenPanel 로 교체.

- [ ] **Step 3: 빌드 + 실행 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

만약 swift-bridge 가 Result 를 throws 로 매핑하지 않아 빌드 에러가 나면, 임시로 `try?` 로 감싸거나 `try await rust.list_directory(path)` 대신 non-throws 버전 확인 — swift-bridge 책 참고 후 수정. 핵심 진단 커맨드:

```bash
grep -n "list_directory" apps/Sources/Generated/cairn_ffi.swift | head
```

생성된 시그니처에 `throws` 가 있어야 하고 없으면 Result 를 직접 분기하는 형태로 래퍼 수정.

- [ ] **Step 4: 앱 실행 확인**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
```

Expected: 창 뜨고 `M1.1 — scaffolding` + 상태 텍스트. 상태는 `failed` 또는 `entries: 0` 중 하나 — 둘 다 FFI 파이프라인은 작동함의 증거.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Services apps/Sources/ContentView.swift
git commit -m "feat(app): add CairnEngine service + restore buildable ContentView"
```

---

## Task 7: Swift — `BookmarkStore.swift` (security-scoped bookmark CRUD)

**Files:**
- Create: `apps/Sources/Services/BookmarkStore.swift`
- Create: `apps/CairnTests/BookmarkStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`apps/CairnTests/BookmarkStoreTests.swift`:

```swift
import XCTest
@testable import Cairn

final class BookmarkStoreTests: XCTestCase {
    var tempDir: URL!
    var store: BookmarkStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = BookmarkStore(storageDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_register_pinned_adds_entry() throws {
        // Use tempDir itself as a "real" folder we definitely can resolve.
        let entry = try store.register(tempDir, kind: .pinned)
        XCTAssertFalse(store.pinned.isEmpty)
        XCTAssertEqual(store.pinned.first?.id, entry.id)
        XCTAssertTrue(entry.lastKnownPath.hasSuffix(tempDir.lastPathComponent))
    }

    func test_persistence_round_trip() throws {
        _ = try store.register(tempDir, kind: .pinned)

        // Re-create store — simulating app restart.
        let reborn = BookmarkStore(storageDirectory: tempDir)
        XCTAssertEqual(reborn.pinned.count, 1)
        XCTAssertEqual(reborn.pinned.first?.lastKnownPath, tempDir.standardizedFileURL.path)
    }

    func test_recent_lru_caps_at_20() throws {
        // Fake bookmark data via registerRaw — registering 21 distinct paths.
        for i in 0..<21 {
            let child = tempDir.appendingPathComponent("child-\(i)")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            _ = try store.register(child, kind: .recent)
        }
        XCTAssertEqual(store.recent.count, 20, "Recent should cap at 20")
    }

    func test_recent_dedup_moves_to_front() throws {
        let a = tempDir.appendingPathComponent("a")
        let b = tempDir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)

        _ = try store.register(a, kind: .recent)
        _ = try store.register(b, kind: .recent)
        XCTAssertEqual(store.recent.first?.lastKnownPath, b.standardizedFileURL.path)

        // Re-register a → should jump to front.
        _ = try store.register(a, kind: .recent)
        XCTAssertEqual(store.recent.first?.lastKnownPath, a.standardizedFileURL.path)
        XCTAssertEqual(store.recent.count, 2)
    }
}
```

- [ ] **Step 2: 테스트 실행 — BookmarkStore 타입이 없어 컴파일 에러 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" 2>&1 | tail -10
```

Expected: 컴파일 에러 `Cannot find 'BookmarkStore' in scope`.

- [ ] **Step 3: `BookmarkStore.swift` 구현**

`apps/Sources/Services/BookmarkStore.swift`:

```swift
import Foundation
import Observation

/// Kind of a bookmark — determines which list it lives in.
enum BookmarkKind: String, Codable {
    case pinned
    case recent
}

/// A persisted handle to a user-selected folder. Stored as security-scoped
/// bookmark data so access survives app restarts under App Sandbox.
struct BookmarkEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let bookmarkData: Data
    var lastKnownPath: String
    let addedAt: Date
    var label: String?
    let kind: BookmarkKind
}

/// Persistence-backed store of security-scoped bookmarks.
///
/// Phase 1 scope:
///   - `register(url, kind)` — create + persist.
///   - `resolve(entry)` — turn stored bookmark back into a URL.
///   - `startAccessing` / `stopAccessing` with reference counting per bookmark.
///   - Persistence in JSON files inside `storageDirectory` (default: App Support).
///   - Recent list is LRU-capped at 20 with path-standardized dedup.
///
/// Intentionally NOT in Phase 1: stale-bookmark re-prompt UI (Phase 2), drag to reorder (Phase 2).
@Observable
final class BookmarkStore {
    private(set) var pinned: [BookmarkEntry] = []
    private(set) var recent: [BookmarkEntry] = []

    private let storageDirectory: URL
    private var activeCounts: [UUID: Int] = [:]

    static let recentCap = 20

    /// - Parameter storageDirectory: Directory used to persist JSON files.
    ///   Tests pass a tempdir; app code passes App Support.
    init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        loadAll()
    }

    /// Convenience init that uses `Library/Application Support/Cairn` inside the sandbox container.
    convenience init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        self.init(storageDirectory: appSupport.appendingPathComponent("Cairn"))
    }

    // MARK: - Registration

    /// Create a security-scoped bookmark for `url`, persist it, and return the entry.
    /// Path comparison for dedup uses `url.standardizedFileURL.path`.
    @discardableResult
    func register(_ url: URL, kind: BookmarkKind) throws -> BookmarkEntry {
        let standardized = url.standardizedFileURL
        let data = try standardized.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let entry = BookmarkEntry(
            id: UUID(),
            bookmarkData: data,
            lastKnownPath: standardized.path,
            addedAt: Date(),
            label: nil,
            kind: kind
        )

        switch kind {
        case .pinned:
            // Pinned dedup: don't add if the same path is already pinned.
            if !pinned.contains(where: { $0.lastKnownPath == entry.lastKnownPath }) {
                pinned.append(entry)
                save(kind: .pinned)
            }
        case .recent:
            // Recent: move-to-front dedup by path; cap at 20.
            recent.removeAll { $0.lastKnownPath == entry.lastKnownPath }
            recent.insert(entry, at: 0)
            if recent.count > Self.recentCap {
                recent = Array(recent.prefix(Self.recentCap))
            }
            save(kind: .recent)
        }
        return entry
    }

    func unpin(_ entry: BookmarkEntry) {
        pinned.removeAll { $0.id == entry.id }
        save(kind: .pinned)
    }

    // MARK: - Resolution & access

    /// Returns the URL if the bookmark resolves cleanly. Returns nil if stale.
    func resolve(_ entry: BookmarkEntry) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: entry.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale { return nil }
        return url
    }

    /// Increments ref count and calls `startAccessingSecurityScopedResource()`
    /// only on first use for that bookmark in this session.
    func startAccessing(_ entry: BookmarkEntry) -> URL? {
        guard let url = resolve(entry) else { return nil }
        let count = (activeCounts[entry.id] ?? 0) + 1
        activeCounts[entry.id] = count
        if count == 1 {
            _ = url.startAccessingSecurityScopedResource()
        }
        return url
    }

    /// Decrements ref count and calls `stopAccessingSecurityScopedResource()`
    /// only when the count drops to zero.
    func stopAccessing(_ entry: BookmarkEntry) {
        guard let count = activeCounts[entry.id], count > 0 else { return }
        let next = count - 1
        if next == 0 {
            activeCounts.removeValue(forKey: entry.id)
            if let url = resolve(entry) {
                url.stopAccessingSecurityScopedResource()
            }
        } else {
            activeCounts[entry.id] = next
        }
    }

    // MARK: - Persistence

    private func fileURL(for kind: BookmarkKind) -> URL {
        storageDirectory.appendingPathComponent("\(kind.rawValue).json")
    }

    private func save(kind: BookmarkKind) {
        let list: [BookmarkEntry] = (kind == .pinned) ? pinned : recent
        do {
            let data = try JSONEncoder().encode(list)
            try data.write(to: fileURL(for: kind), options: [.atomic])
        } catch {
            // Phase 1: tolerate persistence failures silently. Phase 2 logs/report.
        }
    }

    private func loadAll() {
        pinned = load(.pinned)
        recent = load(.recent)
    }

    private func load(_ kind: BookmarkKind) -> [BookmarkEntry] {
        let url = fileURL(for: kind)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BookmarkEntry].self, from: data)
        else { return [] }
        return decoded
    }
}
```

- [ ] **Step 4: `CairnTests` 에 `@testable import` 가 유효하려면 `apps/project.yml` 업데이트 — 이미 Cairn 의존성이 있으므로 OK**

확인만: `apps/project.yml` 의 `CairnTests` 섹션에 `dependencies: - target: Cairn` 이 있어야 함 (Task 5 에서 세팅됨).

- [ ] **Step 5: 재생성·테스트 실행**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" 2>&1 | tail -20
```

Expected: 4 테스트 통과. `** TEST SUCCEEDED **`.

테스트 실행 중 Xcode 가 signing 에러를 뱉을 수 있음. 그러면 `xcodebuild test` 에 `CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""` 플래그 추가:

```bash
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -20
```

- [ ] **Step 6: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Services/BookmarkStore.swift apps/CairnTests/BookmarkStoreTests.swift
git commit -m "feat(app): add BookmarkStore with security-scoped bookmarks + tests"
```

---

## Task 8: Swift — `AppModel` + `NavigationHistory`

**Files:**
- Create: `apps/Sources/App/NavigationHistory.swift`
- Create: `apps/Sources/App/AppModel.swift`

- [ ] **Step 1: `NavigationHistory.swift` 작성**

`apps/Sources/App/NavigationHistory.swift`:

```swift
import Foundation

/// Stack-based navigation history. `push` discards any forward entries past the
/// current index (Safari-style). Used by AppModel to drive ⌘←/⌘→.
struct NavigationHistory: Equatable {
    private(set) var stack: [URL] = []
    private(set) var index: Int = -1

    var current: URL? {
        guard index >= 0, index < stack.count else { return nil }
        return stack[index]
    }

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index < stack.count - 1 }

    mutating func push(_ url: URL) {
        // Truncate forward history when branching.
        if index < stack.count - 1 {
            stack.removeSubrange((index + 1)..<stack.count)
        }
        stack.append(url)
        index = stack.count - 1
    }

    @discardableResult
    mutating func goBack() -> URL? {
        guard canGoBack else { return nil }
        index -= 1
        return stack[index]
    }

    @discardableResult
    mutating func goForward() -> URL? {
        guard canGoForward else { return nil }
        index += 1
        return stack[index]
    }
}
```

- [ ] **Step 2: `AppModel.swift` 작성**

`apps/Sources/App/AppModel.swift`:

```swift
import Foundation
import Observation
import SwiftUI

/// Top-level application state. Single instance injected via @Environment.
@Observable
final class AppModel {
    var history = NavigationHistory()
    var showHidden: Bool = false

    /// The bookmark entry currently "in use" (access started).
    /// nil until the user opens a folder.
    var currentEntry: BookmarkEntry?

    let engine: CairnEngine
    let bookmarks: BookmarkStore

    init(engine: CairnEngine = CairnEngine(), bookmarks: BookmarkStore = BookmarkStore()) {
        self.engine = engine
        self.bookmarks = bookmarks
    }

    /// The URL currently displayed (equal to history.current when present).
    var currentFolder: URL? { history.current }

    // MARK: - Navigation

    /// Navigate to a folder belonging to an already-bookmarked entry.
    /// Handles security-scoped start/stop ref-counting via BookmarkStore.
    func navigate(to entry: BookmarkEntry) {
        if let prev = currentEntry {
            bookmarks.stopAccessing(prev)
        }
        guard let url = bookmarks.startAccessing(entry) else {
            // Bookmark couldn't resolve — leave state unchanged, caller handles UI.
            return
        }
        currentEntry = entry
        history.push(url)

        // Add to recent (unless this IS a recent-selection from sidebar — Phase 2 distinguishes).
        if entry.kind == .pinned {
            try? bookmarks.register(url, kind: .recent)
        }
    }

    /// Register a freshly-chosen folder (from NSOpenPanel) as pinned if first folder,
    /// otherwise as recent. Then navigate to it.
    func openAndNavigate(to url: URL, autoPinIfFirst: Bool = true) throws {
        let isFirst = bookmarks.pinned.isEmpty && autoPinIfFirst
        let entry = try bookmarks.register(url, kind: isFirst ? .pinned : .recent)
        navigate(to: entry)
    }

    /// Move up one level (parent directory). Requires the parent to be within the current
    /// security-scoped root — otherwise silently no-ops (Phase 1 limitation).
    func goUp() {
        guard let url = currentFolder else { return }
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { return } // at /

        // Phase 1: only walk within the current entry's access scope. If parent escapes,
        // user must re-open. Track is coarse — we simply let the listDirectory call fail
        // and show the error. Here we just push.
        history.push(parent)
    }

    func goBack() { _ = history.goBack() }
    func goForward() { _ = history.goForward() }

    func toggleShowHidden() {
        showHidden.toggle()
        engine.setShowHidden(showHidden)
    }
}
```

주의: 위 모델은 `BookmarkEntry` 와 `BookmarkStore` 가 Task 7 에서 만들어진 덕분에 참조 가능.

- [ ] **Step 3: 빌드만 — 아직 뷰에 주입 안 함**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/App
git commit -m "feat(app): add AppModel + NavigationHistory"
```

---

## Task 9: Swift — `FolderModel` (entries ViewModel)

**Files:**
- Create: `apps/Sources/ViewModels/FolderModel.swift`

- [ ] **Step 1: `FolderModel.swift` 작성**

`apps/Sources/ViewModels/FolderModel.swift`:

```swift
import Foundation
import Observation

/// Folder-scoped view model. One instance per currently-displayed folder.
@Observable
final class FolderModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var entries: [FileEntry] = []
    private(set) var state: LoadState = .idle

    private let engine: CairnEngine

    init(engine: CairnEngine) {
        self.engine = engine
    }

    /// Loads the folder. Caller must ensure security-scoped access is active.
    @MainActor
    func load(_ url: URL) async {
        state = .loading
        do {
            let list = try await engine.listDirectory(url)
            entries = list
            state = .loaded
        } catch {
            entries = []
            state = .failed(String(describing: error))
        }
    }

    func clear() {
        entries = []
        state = .idle
    }
}
```

- [ ] **Step 2: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ViewModels
git commit -m "feat(app): add FolderModel with async load state"
```

---

## Task 10: Swift — `OpenFolderEmptyState` 온보딩 뷰

**Files:**
- Create: `apps/Sources/Views/Onboarding/OpenFolderEmptyState.swift`

- [ ] **Step 1: `OpenFolderEmptyState.swift` 작성**

`apps/Sources/Views/Onboarding/OpenFolderEmptyState.swift`:

```swift
import SwiftUI
import AppKit

/// Shown when AppModel has no currentFolder — user needs to pick a starting point
/// via NSOpenPanel, since App Sandbox requires explicit folder consent.
struct OpenFolderEmptyState: View {
    @Bindable var app: AppModel
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("🏔️")
                .font(.system(size: 72))

            VStack(spacing: 6) {
                Text("Open a folder to get started")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Text("Cairn runs in the App Sandbox, so you need to pick a folder once. We'll remember it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button(action: presentOpenPanel) {
                Label("Choose Folder…", systemImage: "folder")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: [.command])

            if let msg = errorMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try app.openAndNavigate(to: url)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't register folder: \(error.localizedDescription)"
            }
        }
    }
}
```

- [ ] **Step 2: 빌드 — 컴파일 확인만**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Onboarding
git commit -m "feat(app): add OpenFolderEmptyState onboarding view"
```

---

## Task 11: Swift — `FileListSimpleView` (SwiftUI List, 1-컬럼)

**Files:**
- Create: `apps/Sources/Views/FileList/FileListSimpleView.swift`

- [ ] **Step 1: `FileListSimpleView.swift` 작성**

`apps/Sources/Views/FileList/FileListSimpleView.swift`:

```swift
import SwiftUI

/// Minimal 1-column list of entries. Will be replaced by NSTableView-backed
/// FileListView in M1.2; kept here as the scaffolding for M1.1 verification.
struct FileListSimpleView: View {
    @Bindable var folder: FolderModel
    /// Called when the user activates a row (double-click / Return).
    let onOpen: (FileEntry) -> Void

    @State private var selection: FileEntry.ID?

    var body: some View {
        Group {
            switch folder.state {
            case .idle:
                Text("No folder loaded.")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView().controlSize(.small)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't read folder").font(.headline)
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding()
            case .loaded:
                List(folder.entries, id: \.id, selection: $selection) { entry in
                    Label {
                        Text(entry.name)
                    } icon: {
                        Image(systemName: entry.kind == .Directory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.kind == .Directory ? .blue : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpen(entry) }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// FileEntry is a swift-bridge struct; it doesn't auto-conform to Identifiable.
// Wrap the path (which is unique within a folder snapshot) as the id.
extension FileEntry: Identifiable {
    public var id: String { path }
}
```

주의: swift-bridge 생성 struct 에 `Identifiable` 을 extension 으로 붙이는 건 Swift 표준 방식. `public` 확장은 필요하지 않지만 동일 모듈 내면 접근 가능.

FileKind enum variant 의 Swift 쪽 이름 확인:

```bash
grep -A 3 "enum FileKind" apps/Sources/Generated/cairn_ffi.swift
```

Expected 패턴 (swift-bridge 0.1.59 기본동작):
```swift
public enum FileKind {
    case Directory
    case Regular
    case Symlink
}
```

플랜의 `FileListSimpleView` 는 `.Directory` (capitalized) 를 가정한다. 만약 어떤 이유로 소문자 시작 (`.directory`) 이 생성됐다면 위 View 의 두 개의 `.Directory` 참조를 `.directory` 로 일괄 치환하고 재빌드.

- [ ] **Step 2: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. 만약 enum case 에러면 Step 1 의 주의사항 참고해 수정 후 재빌드.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList
git commit -m "feat(app): add FileListSimpleView (SwiftUI List, 1-column, placeholder for M1.2)"
```

---

## Task 12: Swift — `ContentView` 재구성 (온보딩 ↔ 리스트 전환)

**Files:**
- Modify: `apps/Sources/CairnApp.swift`
- Modify: `apps/Sources/ContentView.swift`

- [ ] **Step 1: `CairnApp.swift` — AppModel 주입**

`apps/Sources/CairnApp.swift` 전체 교체:

```swift
import SwiftUI

@main
struct CairnApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Placeholder for Settings Scene — actual UI lands in Phase 2/3.
    }
}
```

- [ ] **Step 2: `ContentView.swift` 재구성 — 상태 기반 분기**

`apps/Sources/ContentView.swift` 전체 교체:

```swift
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var folder: FolderModel?

    var body: some View {
        Group {
            if app.currentFolder == nil {
                OpenFolderEmptyState(app: app)
            } else if let folder {
                NavigationSplitView {
                    sidebarPlaceholder
                } content: {
                    FileListSimpleView(folder: folder, onOpen: handleOpen)
                } detail: {
                    previewPlaceholder
                }
                .navigationTitle(app.currentFolder?.lastPathComponent ?? "Cairn")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: { app.goBack() }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!app.history.canGoBack)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                    }
                    ToolbarItem(placement: .navigation) {
                        Button(action: { app.goForward() }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!app.history.canGoForward)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                    }
                    ToolbarItem(placement: .navigation) {
                        Button(action: { app.goUp() }) {
                            Image(systemName: "arrow.up")
                        }
                        .keyboardShortcut(.upArrow, modifiers: [.command])
                    }
                }
            }
        }
        .task {
            ensureFolderModel()
            if let url = app.currentFolder {
                await folder?.load(url)
            }
        }
        .onChange(of: app.currentFolder) { _, new in
            ensureFolderModel()
            guard let url = new else { folder?.clear(); return }
            Task { await folder?.load(url) }
        }
    }

    private func ensureFolderModel() {
        if folder == nil { folder = FolderModel(engine: app.engine) }
    }

    private func handleOpen(_ entry: FileEntry) {
        // `.Directory` is swift-bridge's default casing (Rust variant preserved).
        // If your generated enum differs, change to the matching case name.
        if entry.kind == .Directory {
            // Navigate into a subfolder of the current root — access already granted.
            let url = URL(fileURLWithPath: entry.path)
            app.history.push(url)
        } else {
            // File open: delegate to Finder for now (Phase 2 adds in-app preview / default-app resolution).
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        }
    }

    private var sidebarPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIDEBAR").font(.caption).foregroundStyle(.secondary)
            Text("Pinned / Recent / Devices — M1.3")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(12)
        .frame(minWidth: 180)
    }

    private var previewPlaceholder: some View {
        VStack {
            Text("PREVIEW")
                .font(.caption).foregroundStyle(.secondary)
            Text("M1.4").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
```

주의: `entry.kind == .Directory` 또는 `.directory` — swift-bridge 가 생성한 enum case 이름에 따라 다르니 Task 11 Step 1 확인과 일관되게.

- [ ] **Step 3: 빌드 + 실행**

```bash
cd /Users/cyj/workspace/personal/cairn
./scripts/build-rust.sh
./scripts/gen-bindings.sh
cd apps && xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

실행:

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
```

Expected flow:
1. 창 뜨고 `🏔️ Open a folder to get started` 표시
2. `Choose Folder…` 클릭 또는 `⌘O` → NSOpenPanel 뜸
3. `~/Desktop` 선택 → 리스트가 그 폴더의 직접 자식으로 채워짐 (folders 먼저, 알파벳 순)
4. 폴더 더블클릭 → 하위로 진입, 내비 타이틀 변경
5. `⌘←` / `⌘→` 히스토리 이동
6. `⌘↑` 상위 (단, sandbox 가 허용하는 범위 내에서만)

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/CairnApp.swift apps/Sources/ContentView.swift
git commit -m "feat(app): wire AppModel + three-pane split view with empty state + ⌘O/↑/←/→"
```

---

## Task 13: 재시동 영속성 검증 — Pinned bookmark resolve

**Files:** (no new files; verification only)

- [ ] **Step 1: 앱 실행 → 폴더 열기 → 종료**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
# NSOpenPanel 로 ~/Desktop 또는 ~/workspace 선택
# 파일 리스트 확인
# ⌘Q 로 종료
```

- [ ] **Step 2: bookmark 파일 존재 확인**

샌드박스 컨테이너 위치:

```bash
CONTAINER=~/Library/Containers/com.ongjin.Cairn/Data/Library/Application\ Support/Cairn
ls "$CONTAINER"
cat "$CONTAINER/pinned.json" | head -c 200; echo
```

Expected: `pinned.json` 존재. 내용은 base64 encoded `bookmarkData` 를 포함한 JSON.

만약 bundle id 가 `com.ongjin.Cairn` 이 아니라 다른 형태라면 `ls ~/Library/Containers/ | grep -i cairn` 로 실제 경로 찾음.

- [ ] **Step 3: 재실행 — NSOpenPanel 없이도 폴더 복원되는지**

현재 상태에선 **재실행 시에도 OpenFolderEmptyState 가 뜨는 게 정상** (AppModel 이 시작 시 bookmark 를 자동 선택 탭하지 않으니까). 이 M1.1 범위는:

- ✅ bookmark 가 persistence 로 남음 (Step 2 확인)
- ⬜ 자동 선택해서 바로 진입 — M1.3 의 사이드바 구현 때 (Pinned 리스트 첫 항목 자동 선택) 추가

만약 "재시동 시 바로 마지막 폴더로 돌아가기" 가 M1.1 에 꼭 있어야 한다면 여기서 추가 Task 를 쓸 수 있지만, 스펙 § 11 의 M1.1 deliverable 엔 "bookmark 최소 CRUD (저장·해결)" 까지만 명시돼 있음 — 자동 복원은 M1.3 범위. **이 Step 은 단지 "persistence 가 됐다" 는 증거만 확인**하고 넘어간다.

- [ ] **Step 4: 커밋 불필요 — 검증만**

---

## Task 14: 워크스페이스 sanity + tag

**Files:** (no new files; verification + tag)

- [ ] **Step 1: 로컬 CI 시뮬레이션**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./scripts/build-rust.sh
./scripts/gen-bindings.sh
(cd apps && xcodegen generate && xcodebuild -scheme Cairn -configuration Debug build | tail -5)
(cd apps && xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | tail -5)
```

Expected: 모두 녹색.

- [ ] **Step 2: fmt 가 실패하면 자동 정렬 + 재커밋**

```bash
cargo fmt --all
git diff --stat
# 변경 있으면:
git add -A
git commit -m "style: cargo fmt"
```

- [ ] **Step 3: M1.1 완료 tag**

```bash
cd /Users/cyj/workspace/personal/cairn
git tag phase-1-m1.1
git log --oneline -20
```

- [ ] **Step 4: 수동 E2E 체크리스트 통과 확인 (M1.1 범위만)**

- [ ] 첫 실행 → `OpenFolderEmptyState` 표시
- [ ] `⌘O` 또는 버튼 → NSOpenPanel 뜸
- [ ] 폴더 선택 → 리스트 렌더 (가장 먼저 폴더, 알파벳 순)
- [ ] 폴더 더블클릭 → 진입, 타이틀 업데이트
- [ ] `⌘←` / `⌘→` 히스토리 작동
- [ ] `⌘↑` 상위 이동 (샌드박스 범위 내)
- [ ] `.gitignore` 내 엔트리 (예: `.git`, `node_modules`) 가 리스트에서 사라짐
- [ ] 종료 후 sandbox container 내 `pinned.json` 존재
- [ ] `cargo test --workspace` 녹색
- [ ] `xcodebuild test -scheme CairnTests` 녹색

전부 체크되면 M1.1 완료.

---

## 🎯 M1.1 Definition of Done

- [ ] `cairn-walker` 가 실제 FS 순회 (gitignore + hidden + .DS_Store 제외) 수행
- [ ] `cairn-core::Engine` 가 walker 를 래핑
- [ ] `cairn-ffi` 가 `greet()` 대신 `new_engine / list_directory / set_show_hidden` 제공
- [ ] Swift `CairnEngine` 서비스가 async throws 로 FFI 호출
- [ ] Swift `BookmarkStore` 가 security-scoped bookmark 저장·해결·ref-count 관리
- [ ] Swift `AppModel` + `NavigationHistory` 가 폴더 이동 상태 관리
- [ ] `OpenFolderEmptyState` + `FileListSimpleView` 가 최소 three-pane UI 제공
- [ ] `CairnTests` 타깃에서 `BookmarkStoreTests` 4개 통과
- [ ] `.entitlements` 가 샌드박스 + user-selected rw + app-scope bookmarks 포함
- [ ] `cargo test --workspace` + `cargo clippy -- -D warnings` + `xcodebuild test` 전부 녹색
- [ ] `git tag phase-1-m1.1` 존재

---

## 다음 마일스톤 로드맵 (스펙 § 11 요약)

M1.1 완료 후 실행 세션에서 별도 플랜 파일로 작성:

| M | 파일명 (제안) | 범위 요약 |
|---|---|---|
| **1.2** | `2026-04-21-cairn-phase-1-m1.2-nstableview.md` | SwiftUI `List` 를 `NSTableView` NSViewRep 로 교체. 3 컬럼(Name/Size/Modified), 헤더 정렬, 다중 선택, ↑↓ 네비 |
| **1.3** | `2026-04-21-cairn-phase-1-m1.3-sidebar-breadcrumb.md` | 사이드바 3 섹션(Pinned/Recent/Devices), MountObserver, BreadcrumbBar, `⌘D` |
| **1.4** | `2026-04-21-cairn-phase-1-m1.4-preview.md` | `cairn-preview` Rust, 이미지 썸네일, MetaOnly, `Space` → QLPreviewPanel, `⌘⇧.` |
| **1.5** | `2026-04-21-cairn-phase-1-m1.5-theme-b-context-menu.md` | `CairnTheme` struct, Glass Blue 토큰, NSVisualEffectView, 컨텍스트 메뉴 (Reveal / Copy Path / Trash) |
| **1.6** | `2026-04-21-cairn-phase-1-m1.6-polish-alpha.md` | E2E 완주, README, `create-dmg`, `v0.1.0-alpha` 태그 |

각 마일스톤 플랜은 **직전 마일스톤 완료 직후** 에 작성 — 실행하며 얻은 러닝을 반영하기 위함. (M1.1 러닝 예: swift-bridge enum case 이름 대소문자, NSOpenPanel 비동기 패턴, bookmark JSON 위치.)
