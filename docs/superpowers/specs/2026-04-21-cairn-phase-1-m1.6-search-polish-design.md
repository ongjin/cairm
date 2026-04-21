# Cairn Phase 1 · M1.6 — Search + Polish + v0.1.0-alpha (Design Spec)

**Parent spec:** `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md` (§ 11 M1.6)
**Predecessor milestone:** M1.5 (tag `phase-1-m1.5`) — Glass Blue theme + context menu + sidebar highlight + `⌘R`
**Date:** 2026-04-21
**Stance:** Finder replacement (spec 상 Phase 2 였던 search 일부를 M1.6 로 당김; pivot memory `project_finder_replacement_pivot.md` 참조)

---

## 1. 목표

Cairn 을 **Finder-replacement 로서 v0.1.0-alpha** 로 낼 수 있는 상태로 만든다. 즉:

1. **Search** — `⌘F` inline 검색 (folder-local filter + subtree recursive walk 두 가지 scope). 기존 NSTableView / 컨텍스트 메뉴 / 프리뷰 / 정렬 재사용.
2. **Polish** — M1.2 ~ M1.5 의 이월된 코드/UX 개선 전부 흡수 (리스트는 § 7).
3. **Release** — E2E 체크리스트 완주, README/USAGE 문서, `create-dmg` 실험, tag `phase-1-m1.6` + `v0.1.0-alpha`.

M1.6 는 parent spec 의 원 scope (polish + alpha) 를 유지하면서 search 를 **최소한의 형태로** 추가한다. Full Phase 2 search (`⌘K` palette, `cairn-index` redb persistent index, FSEvents, content search, fuzzy) 는 **Phase 2 로 유지**.

## 2. Search 범위 (Locked)

### 2.1 들어가는 것

- `⌘F` → toolbar `NSSearchField` focus
- Scope 토글: **This Folder** (in-memory filter) | **Subtree** (recursive walk)
- Substring match, **대소문자 무시** (`localizedCaseInsensitiveContains`)
- `.gitignore` 존중 — FolderModel.showHidden 설정과 동일한 룰
- Streaming partial results (Subtree) — 256-entry batch, running-sort, max 5000 cap
- 결과 listing 은 기존 `NSTableView` 재사용. Subtree 모드에서 **Folder 컬럼** 자동 추가 (search root 기준 상대경로)
- `Esc` 또는 빈 쿼리 → 정상 폴더 뷰로 복귀
- `currentFolder` 변경 시 query 유지하고 새 root 에서 자동 재검색 (Finder 와 다름, power-user 편의)

### 2.2 안 들어가는 것 (Phase 2 +)

- 내용 기반 검색 (파일 안의 텍스트 grep)
- Fuzzy / regex / glob matching
- Persistent index (`cairn-index` redb)
- FSEvents 구독으로 실시간 동기화
- `⌘K` command palette
- 글로벌 (This Mac) scope
- Saved searches, Smart Folders
- 검색 결과 export

---

## 3. 아키텍처

### 3.1 레이어 다이어그램

```
┌──────────────────────────────── macOS app ────────────────────────────────┐
│                                                                             │
│  ContentView ── toolbar: NSSearchField + scope Picker (⌘F → focus)         │
│         │         ↕                                                         │
│         │      SearchModel (new @Observable)                                │
│         │         ├─ query: String                                          │
│         │         ├─ scope: .folder | .subtree                              │
│         │         ├─ results: [FileEntry]   (running-sort, cap 5000)        │
│         │         ├─ phase:  .idle | .running | .capped | .done | .failed  │
│         │         ├─ hitCount: Int                                          │
│         │         └─ task: Task<Void, Never>?                               │
│         ▼                                                                    │
│  FileListView ── binds to SearchModel.results when active,                  │
│                   else FolderModel.sortedEntries (existing M1.2 path)       │
│                                                                              │
│  FileListCoordinator ── menu/preview/sort 재사용.                            │
│                    subtree 모드에서 Folder 컬럼 추가.                        │
│                                                                              │
│  ┌──── FFI (swift-bridge) ────────────────────────────────────────────────┐ │
│  │  search_start(root, query, subtree, show_hidden) -> u64                │ │
│  │  search_next_batch(handle) async -> Option<Vec<FileEntry>>             │ │
│  │  search_cancel(handle)                                                 │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────── Rust ──────────────────────────────────────┘
                                     │
  cairn-search (신규 구현, skeleton 대체)                                      │
                ├─ Session (jwalk iterator + bounded mpsc channel)            │
                ├─ ignore::WalkBuilder (subtree)                              │
                │   or std::fs::read_dir (folder)                             │
                ├─ Arc<AtomicBool> cancel flag                                │
                └─ once_cell::Lazy<Mutex<HashMap<u64, Session>>> registry     │
```

### 3.2 핵심 설계 선택

- **SearchModel 분리** — `FolderModel` 은 건드리지 않음. 기존 load/sort 경로 그대로 유지하면서 ContentView 에서 분기만 추가
- **Result 타입 공유** — Rust `cairn-core::FileEntry` 가 search 결과에도 그대로. NSTableView / 컨텍스트 메뉴 / 프리뷰 / Reveal / Copy Path / Trash 코드 재사용 0 변경
- **Handle 기반 FFI (poll-next-batch)** — swift-bridge 0.1.x 에서 async stream 이 덜 견고함. Polling 패턴이 가장 안전. Swift 측은 `while let batch = await ...` 루프
- **Running-sort** — batch 수신 시 `results.append + sort(by: descriptor)`. 5000 항 정렬은 Swift 에서 <1ms
- **Debounce (subtree only)** — 200ms debounce 로 keystroke 마다의 task spawn/cancel 스톰 방지. Folder mode 는 in-memory 라 debounce 없이도 즉시 OK
- **Session registry** — Rust 측 `HashMap<u64, Session>` + `Mutex`. Handle 은 monotonic u64. Swift 는 handle 만 보유

---

## 4. Rust 크레이트 API

### 4.1 `cairn-search` (skeleton 실구현)

```rust
// crates/cairn-search/src/lib.rs

use cairn_core::{FileEntry, FileKind};
use std::path::{Path, PathBuf};

pub struct SearchHandle(pub u64);

pub enum SearchMode {
    Folder,   // depth 1, non-recursive
    Subtree,  // recursive, ignore::WalkBuilder
}

pub enum SearchStatus {
    Running,
    Capped,
    Done,
    Failed(String),
}

pub struct SearchOptions {
    pub query: String,
    pub mode: SearchMode,
    pub show_hidden: bool,
    pub result_cap: usize,    // default 5000
    pub batch_size: usize,    // default 256
}

/// Starts a background walker and returns a handle.
/// Non-blocking: the walker thread is spawned immediately and begins producing
/// batches. Use `next_batch` to pull results.
pub fn start(root: &Path, opts: SearchOptions) -> SearchHandle;

/// Pulls up to `batch_size` matching entries. Blocks up to 100ms waiting.
/// Returns `None` when the walker has finished (done / capped / cancelled / failed).
/// Must be called repeatedly until `None`.
pub fn next_batch(h: SearchHandle) -> Option<Vec<FileEntry>>;

/// Returns current status (monotonic: Running → Capped / Done / Failed).
pub fn status(h: SearchHandle) -> SearchStatus;

/// Sets the cancel flag; ongoing walk stops at next iteration check.
/// Idempotent. Safe on invalid handles (no-op).
pub fn cancel(h: SearchHandle);
```

**Deps:**
```toml
[dependencies]
cairn-core = { path = "../cairn-core" }
ignore = "0.4"
once_cell = "1"
thiserror = { workspace = true }

[dev-dependencies]
tempfile = "3"
```

**Internal types (not exported):**

```rust
struct Session {
    cancel: Arc<AtomicBool>,
    rx: mpsc::Receiver<Vec<FileEntry>>,
    status: Arc<Mutex<SearchStatus>>,
    _thread: JoinHandle<()>,  // walker thread; dropped on cancel/done
}

static REGISTRY: Lazy<Mutex<HashMap<u64, Session>>> = ...;
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);
```

**Walker thread logic (subtree):**

```
WalkBuilder::new(root)
  .hidden(!show_hidden)            // show_hidden off → skip dotfiles
  .git_ignore(!show_hidden)        // off → respect .gitignore
  .build()
  .for_each(entry):
    if cancel.load(): break
    let name = entry.file_name().to_string_lossy()
    if name.to_lowercase().contains(&query_lower):
      buffer.push(FileEntry::from(entry))
      matched += 1
      if matched >= result_cap: status = Capped; cancel.set(true); break
      if buffer.len() >= batch_size: tx.send(buffer.drain(..).collect())
  if !buffer.is_empty(): tx.send(buffer)
  // tx dropped → receiver gets None
  status = if Capped { Capped } else if Cancelled { Done } else { Done }
```

### 4.2 `cairn-walker` (변경 없음)

M1.1 의 `list_directory` 그대로. Search 는 별도 crate 에서 `ignore::WalkBuilder` 직접 사용 (walker crate 의 API 는 depth 1 용).

### 4.3 `cairn-ffi` (확장)

```rust
// crates/cairn-ffi/src/lib.rs  — swift_bridge 블록 확장

#[swift_bridge::bridge]
mod ffi {
    extern "Rust" {
        // 기존 API (list_directory, preview_text, ...)
        // ...

        // 신규
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
    }
}
```

**Deps 업데이트:**

```toml
# crates/cairn-ffi/Cargo.toml
[dependencies]
cairn-core = { path = "../cairn-core" }
cairn-walker = { path = "../cairn-walker" }
cairn-preview = { path = "../cairn-preview" }    # 유지 (P16 이 쓰게 됨)
cairn-search = { path = "../cairn-search" }      # 신규
swift-bridge = "0.1"
```

Polish 항목 P13 ("unused cairn-preview dep 제거") 는 **retracted** — M1.5 시점엔 미사용이었지만 M1.6 에서 `preview_text(max_bytes=0)` 가드 (P16) 작업으로 다시 활성. 대신 실제 사용 여부를 코드에서 확인.

### 4.4 `cairn-core` (변경 없음 or 최소)

`FileEntry` 재사용. P14 (`WalkerError` re-export 일관성) 만 정리.

---

## 5. Swift 앱 구조

### 5.1 신규 파일

```
apps/Sources/
├── Models/
│   └── SearchModel.swift             (신규)
├── Views/
│   └── Search/
│       └── SearchField.swift         (신규)
└── App/
    └── CairnEngine+Search.swift      (신규, FFI async 래퍼)
```

### 5.2 `SearchModel`

```swift
// apps/Sources/Models/SearchModel.swift

import Foundation
import SwiftUI

enum SearchScope: String { case folder, subtree }

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

    private var task: Task<Void, Never>?
    private var activeHandle: UInt64?
    private let engine: CairnEngine
    private let debounceMs: UInt64 = 200_000_000

    init(engine: CairnEngine) { self.engine = engine }

    var isActive: Bool { !query.isEmpty }

    /// Called when query, scope, currentFolder, showHidden, or sort changes.
    func refresh(
        root: URL,
        showHidden: Bool,
        sort: FolderModel.SortDescriptor,
        folderEntries: [FileEntry]
    ) {
        task?.cancel()
        if let h = activeHandle { engine.searchCancel(handle: h); activeHandle = nil }

        if query.isEmpty {
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

        // subtree mode — debounce + async walker
        phase = .running
        hitCount = 0
        results = []
        let q = query
        let rootPath = root.path
        let hidden = showHidden
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceMs ?? 200_000_000)
            if Task.isCancelled { return }
            let handle = await engine.searchStart(
                root: rootPath, query: q, subtree: true, showHidden: hidden)
            await MainActor.run { self?.activeHandle = handle }
            defer {
                Task { await MainActor.run {
                    if self?.activeHandle == handle { self?.activeHandle = nil }
                } }
                // handle 은 Rust 가 자동 정리 (cancel or done)
            }

            while !Task.isCancelled {
                guard let batch = await engine.searchNextBatch(handle: handle) else { break }
                await MainActor.run {
                    guard let self else { return }
                    self.results.append(contentsOf: batch)
                    self.results.sort(by: Self.comparator(sort))
                    self.hitCount = self.results.count
                    if self.results.count >= 5000 { self.phase = .capped }
                }
            }
            await MainActor.run {
                guard let self else { return }
                if case .running = self.phase { self.phase = .done }
            }
        }
    }

    func cancel() {
        task?.cancel()
        if let h = activeHandle { engine.searchCancel(handle: h) }
        activeHandle = nil
        phase = .idle
    }

    private static func comparator(_ sort: FolderModel.SortDescriptor)
      -> (FileEntry, FileEntry) -> Bool {
        // FolderModel 의 `sortedEntries` 로직을 reusable 스태틱으로 추출
        // (`FolderModel+Sort.swift` 같은 extension 으로 쪼개 SearchModel 이 공유).
        // switch on sort.field: .name / .size / .modified.
        // 각 case 에서 ascending / descending 반영.
        FolderModel.comparator(for: sort)
    }
}
```

### 5.3 `SearchField` View

```swift
// apps/Sources/Views/Search/SearchField.swift

import SwiftUI

struct SearchField: View {
    @Bindable var search: SearchModel
    @FocusState var focused: Bool

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
            }
        }
    }
}
```

### 5.4 `ContentView` 통합

- `@State private var searchModel: SearchModel?` + init 시 `searchModel = SearchModel(engine: app.engine)`
- `ToolbarItem(placement: .automatic) { SearchField(search: searchModel).focused($searchFocused) }`
- Hidden `⌘F` 바인딩:
  ```swift
  Button("") { searchFocused = true }
    .keyboardShortcut("f", modifiers: [.command])
    .hidden()
    .frame(width: 0, height: 0)
  ```
- FileListView entries source 조건 분기:
  ```swift
  let entries: [FileEntry] = searchModel.isActive
      ? searchModel.results
      : (folder?.sortedEntries ?? [])
  FileListView(entries: entries, ...)
  ```
- Reactive triggers (`.onChange`):
  - `searchModel.query` → `searchModel.refresh(...)`
  - `searchModel.scope` → `searchModel.refresh(...)`
  - `app.currentFolder` → `searchModel.refresh(...)` (query 유지, root 바뀜)
  - `folder?.sortDescriptor` → `searchModel.refresh(...)` (subtree 재정렬 위해)
  - `app.showHidden` → `searchModel.refresh(...)`

### 5.5 `FileListView` / `FileListCoordinator` 확장

- 새 파라미터:
  ```swift
  struct FileListView: NSViewRepresentable {
      let entries: [FileEntry]                  // 기존: folder 에서 읽음 → 이제 외부 주입
      let folderColumnVisible: Bool             // 신규
      // ... 나머지 기존 그대로
  }
  ```
- `FileListCoordinator`:
  - `.folder` NSUserInterfaceItemIdentifier 추가
  - `setFolderColumnVisible(_ visible: Bool)` — NSTableColumn 추가/제거
  - `searchRoot: URL?` property — Folder 컬럼 값 계산 (`entry.path` 에서 `searchRoot.path + "/"` 제거)
  - `cellForTableColumn` 의 switch 에 `.folder` case 추가

### 5.6 Result cap banner

```swift
// ContentView 내 FileListView 위에 얹기
if searchModel.phase == .capped {
    HStack {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text("Showing first 5,000 results — refine your query").font(.caption)
        Spacer()
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(Color.orange.opacity(0.15))
}
```

---

## 6. 데이터 흐름

### 6.1 Folder-mode filter (in-memory)

```
⌘F → searchFocused=true → NSSearchField key responder
유저 "r" 입력
  SearchField $search.query = "r"
  ContentView .onChange(of: searchModel.query) → searchModel.refresh(...)
  SearchModel.refresh:
    1. task?.cancel()
    2. scope == .folder: results = folderEntries.filter { name.contains("r") }
    3. phase = .done
  ContentView entries = searchModel.results
  FileListView updateNSView → coordinator.applyModelSnapshot(entries) → NSTableView reloadData
```

### 6.2 Subtree-mode streaming

```
scope toggle → Picker change → searchModel.scope = .subtree
  → ContentView.onChange → refresh
  SearchModel.refresh:
    task?.cancel() (이전 folder-mode task 없지만 FFI handle 없음)
    phase = .running; results = []
    task = Task {
      sleep(200ms) (debounce)
      handle = await engine.searchStart("/Users/me/repo", "TODO", true, false)
        → FFI async: Rust 측 Session 생성 + walker thread spawn
      while (batch = await engine.searchNextBatch(handle)) {
        MainActor: results.append; sort; hitCount += batch.count
        if results.count >= 5000 { phase = .capped }
      }
      MainActor: phase = .done (아직 running 이면)
    }

Batch 흐름 (Rust → Swift):
  Rust walker thread:
    for entry in WalkBuilder::new(root).hidden(!show_hidden).build():
      if cancel.load(): break
      if name.to_lowercase().contains(&query): buffer.push(entry)
      if buffer.len() >= 256: tx.send(buffer.drain())
  Session.next_batch(handle):
    rx.recv_timeout(100ms) 모아서 Vec 반환. disconnected → None.
```

### 6.3 쿼리 변경 중 취소

```
기존 running subtree 도중 유저가 "r" → "re" 입력
  searchModel.refresh:
    1. task?.cancel() → Swift Task 가 CancellationError
    2. engine.searchCancel(handle) → Rust cancel flag true
    3. 새 refresh: 새 handle, 새 task
  Rust 측 기존 walker:
    다음 iteration 에서 cancel 확인, break
    Session 은 status=Done, 자동 drop
```

### 6.4 currentFolder 변경 (검색 유지)

```
유저가 사이드바 Pinned 클릭 → app.currentFolder 변경
  ContentView.onChange(of: app.currentFolder) → searchModel.refresh(root: new, ...)
  → 이전 search task cancel, 새 root 에서 재검색
```

### 6.5 Esc / 빈 쿼리

```
Esc → TextField 기본 동작으로 query clear → onChange → refresh:
  query.isEmpty: task?.cancel(); results=[]; phase=.idle
  ContentView: searchModel.isActive == false → folder.sortedEntries 로 복귀
```

---

## 7. Polish & Performance Carryover

### 7.1 M1.2 ~ M1.5 이월 항목

| # | 항목 | 타겟 파일 | 우선순위 | 비고 |
|---|---|---|---|---|
| P1 | `PreviewModel` `@MainActor` + `compute` 를 `Task.detached` 로 | `apps/Sources/Models/PreviewModel.swift` | High | Swift 6 strict-concurrency 대비 |
| P2 | `ImagePreview` path 변경 시 `image = nil` reset | `apps/Sources/Views/Preview/PreviewRenderers.swift` | Medium | stale 이미지 깜빡임 |
| P3 | `quickLookURLs` → `beginPreviewPanelControl` snapshot 캡처 | `apps/Sources/Views/FileList/FileListCoordinator.swift` | Medium | race 방지 |
| P4 | `urlsForApplications(toOpen:)` 파일 타입 단위 캐시 | `apps/Sources/Views/FileList/FileListCoordinator.swift` | Medium | Open With perf |
| P5 | Open With default-app dedupe: `standardizedFileURL` 비교 | 같음 | Low | M1.5 리뷰 |
| P6 | `displayName(atPath:).replacingOccurrences(".app","")` 제거 | 같음 | Low | M1.5 리뷰 |
| P7 | `Move to Trash` 실패 NSAlert | 같음 | Medium | UX |
| P8 | `representedObject` → `MenuPayload` 통합 refactor | 같음 | Low | OpenWithPayload 와 통합 |
| P9 | `SidebarModelTests` 반응성 테스트 | `apps/Tests/` | Medium | M1.3 잔여 |
| P10 | `sortDescriptorsDidChange` 재진입 주석 | `FileListCoordinator.swift` | Low | M1.2 잔여 |
| P11 | `modified_unix==0` sentinel 주석 | 같음 | Low | M1.2 잔여 |
| P12 | `@Bindable var folder` → `let folder` | `FileListView.swift` | Low | M1.2 잔여 |
| P13 | ~~`cairn-ffi` unused `cairn-preview` dep 제거~~ | retracted — M1.6 search 가 실사용 유지 |
| P14 | `cairn-core` `WalkerError` re-export 일관성 | `crates/cairn-core/src/lib.rs` | Low | — |
| P15 | 모듈 docstring 갱신 (`cairn-core`, `CairnEngine`) | 여러 파일 | Low | — |
| P16 | `preview_text(max_bytes=0)` 가드 | `crates/cairn-preview/src/*` | Medium | crash 방지 |
| P17 | `String(describing: error)` → user-facing mapping | `AppModel.swift` 등 | Medium | UX |
| P18 | `activateSelected` multi-row 동작 정립 | `FileListCoordinator.swift` | Low | M1.2 잔여 |
| P19 | `isPinned(url:)` plan 스펙 drift 정리 | `BookmarkStore.swift` | Low | M1.3 잔여 |

### 7.2 M1.6 특유 새 polish (search 관련)

| # | 항목 | 타겟 | 비고 |
|---|---|---|---|
| N1 | Search batch coalescing (30 FPS cap) | `SearchModel.swift` | UI jitter 방지 |
| N2 | Subtree mode `.gitignore` 존중 여부 toggle | `SearchField.swift` | 현재 showHidden 연동, 독립 토글은 Phase 2 |
| N3 | Result cap 도달 시 banner | `ContentView.swift` | 본편 |
| N4 | Empty-result state ("No matches for <q>") | 같음 | 본편 |

---

## 8. Release 산출물

### 8.1 문서

- **`README.md`** (신규/갱신) — 프로젝트 소개 / 설치 (빌드 from source) / 주요 단축키 / Glass Blue 스크린샷 1-2장 / 현재 상태 (alpha, Phase 1 범위). Phase 2 로드맵 섹션은 parent spec 링크
- **`USAGE.md`** (신규) — E2E 체크리스트 § 9 기반 user-facing 사용 가이드. `⌘F`, `⌘D`, `⌘↑`, sidebar drag-to-pin 등

### 8.2 배포

- **`scripts/make-dmg.sh`** (신규) — `create-dmg` (Homebrew `brew install create-dmg`) 로 미서명 dmg 생성. distribution 등록은 X. 실험 성격
- **Tag:** `git tag phase-1-m1.6` + `git tag v0.1.0-alpha` (둘 다 같은 commit). 원격 push 는 사용자 수동

### 8.3 E2E

Parent spec § 9 체크리스트 완주 + 본 spec § 5.6 search 부록 체크리스트 완주.

---

## 9. 수동 E2E 체크리스트 (M1.6 완료 조건)

### 9.1 Parent spec § 9 (기존)

- [ ] 첫 실행 → NSOpenPanel → `~/workspace` 선택 → 파일 리스트 + 자동 Pinned
- [ ] 파일 더블클릭 / `↵` → 폴더 진입 or `NSWorkspace.open`
- [ ] 브레드크럼 세그먼트 클릭 → 네비 + 히스토리 push
- [ ] `⌘↑` / `⌘←/→` 히스토리, 끝 비활성
- [ ] 컬럼 헤더 클릭 정렬 토글
- [ ] 다중 선택 (`⇧↓`, `⌘클릭`) → 컨텍스트 메뉴 복수 대상
- [ ] 파일 선택 → 프리뷰 (텍스트 2KB / 이미지 썸네일 / meta)
- [ ] `Space` → Quick Look
- [ ] `⌘D` → 현재 폴더 Pinned 추가, 재시동 유지
- [ ] 외장 USB 마운트 → Devices 섹션 즉시 반영
- [ ] `⌘⇧.` 숨김 토글, `.gitignore` 존중 유지
- [ ] 권한 없는 폴더 inline 에러 + 재프롬프트
- [ ] `cargo test --workspace` + `cargo clippy -D warnings` 녹색
- [ ] CI 녹색
- [ ] DMG 빌드 실험

### 9.2 M1.6 search 추가

- [ ] `⌘F` → toolbar search field focus (필드 테두리 강조)
- [ ] Scope Picker: "This Folder" / "Subtree" 토글
- [ ] "This Folder" + 쿼리 → 즉시 필터, NSTableView 갱신
- [ ] "Subtree" + 쿼리 → 200ms 후 walker 시작, batch 단위로 결과 live populate
- [ ] Subtree 결과에 Folder 컬럼 표시 (search root 기준 상대경로)
- [ ] Hit count badge ("123 found") running 중 증가
- [ ] 5000 도달 → 상단 orange 배너 + 더 이상 결과 증가 안 함
- [ ] 검색 중 쿼리 변경 → 이전 walker 취소, 새 쿼리로 재시작
- [ ] 검색 중 scope 토글 → 이전 task 취소, 새 모드로 재시작
- [ ] 검색 중 사이드바 클릭 (폴더 변경) → 이전 취소, 새 root 에서 재검색 (query 유지)
- [ ] `Esc` or 쿼리 clear → 정상 폴더 뷰 복귀
- [ ] 검색 결과에서 `Space` → QL 정상
- [ ] 검색 결과에서 더블클릭 → 파일 열림 or 폴더 진입
- [ ] 검색 결과에서 우클릭 → Reveal / Copy Path / Open With / Move to Trash 모두 정상
- [ ] 검색 결과 컬럼 헤더 클릭 → 정렬 토글 (running-sort)
- [ ] `⌘R` 은 search 활성 상태에선 **현재 폴더만** reload (search 결과는 재검색 아님 — 별도 동작)

### 9.3 Polish 검증

- [ ] `⌘⌫` 로 Trash 실패 시 NSAlert 표시 (P7)
- [ ] Open With 메뉴 여러 번 열어도 끊김 없이 뜸 (P4 cache 확인)
- [ ] Image preview 가 다른 파일 선택 시 이전 이미지 깜빡임 없음 (P2)
- [ ] 검색 중 `⌘Q` 종료 → 다음 실행 시 깨끗하게 복귀 (Session cleanup)

---

## 10. 테스트 전략

### 10.1 Rust (`cairn-search` 신규 테스트)

- `smoke_empty_root` — 빈 tempdir → `start` → 즉시 None
- `folder_mode_matches_only_direct_children` — 1층 매칭, 하위 제외
- `subtree_mode_recursive` — nested tempdir 매칭
- `case_insensitive` — "FOO" → "foobar.txt" 매칭
- `gitignore_respected_when_hidden_off` — `.gitignore` 대상 제외
- `hidden_files_off_skips_dotfiles` — `.git` 디렉터리 제외
- `cancel_mid_walk` — cancel 호출 후 next_batch() None
- `cap_enforcement` — 5001 매칭 fixture → 정확히 5000 + capped status
- `invalid_handle_safe` — cancel/next_batch 가 panic 하지 않음
- `concurrent_sessions` — 세션 2개 동시 run 간섭 없음

### 10.2 Swift (XCTest)

- `SearchModelTests`:
  - `idleByDefault`
  - `folderModeFiltersInMemory`
  - `emptyQueryClearsResults`
  - `cancelClearsTaskAndHandle`
  - `scopeToggleTriggersRefresh`
- `FileListCoordinatorTests` 확장:
  - `folderColumnAppearsInSubtreeMode`
  - `folderColumnRelativePath`

### 10.3 수동 E2E

§ 9 전체 (parent + M1.6 addendum + polish 검증).

---

## 11. 리스크 & 완화

| 리스크 | 완화 |
|---|---|
| swift-bridge 0.1.x 에서 `async fn search_next_batch` 가 예상대로 안 돌면 | 폴백: `fn poll_batch(h) -> Option<Vec<...>>` + Swift 측 `Task.sleep(10ms)` 루프. 기능 동등 |
| Subtree walk 가 `~/` 에서 너무 느려 UI 체감 나쁨 | 5000 cap + 200ms debounce 로 최악 상황 bounded. 배너로 유저에게 알림 |
| Session 누수 (Swift 가 cancel 안 부르고 task 종료) | M1.6 범위에선 최선-노력 정리. 5분 TTL 은 Phase 2 polish |
| M1.6 스코프 팽창 (polish 17항 + search + release 동시) | Polish 우선순위 (High/Medium/Low) 로 구분. Low 는 v0.1.0-alpha 이후 hotfix 가능. Alpha gate 는 search + High/Medium polish + release |
| Search 가 alpha 직전에 버그 많으면 | 플랜에 "search 없이 alpha 태그 분기 가능" 옵션 둠: `v0.1.0-alpha` 를 M1.6.1 로 미루고 `phase-1-m1.6` 는 search + polish 단독 |

---

## 12. 마일스톤 & Tag

- 모든 task 완료 + E2E 통과 시:
  - `git tag phase-1-m1.6`
  - `git tag v0.1.0-alpha`
  - 같은 HEAD
- 이후 Phase 2 진입: `cairn-index` (redb persistent) + FSEvents + `⌘K` palette + content search + fuzzy

---

## 13. 부록: 데이터 플로우 (Subtree 검색 전체 왕복)

```
유저가 sidebar Pinned 클릭
  → AppModel.navigate(to: url) → currentFolder 변경
  → ContentView.onChange(currentFolder) → SearchModel.refresh
    query="TODO", scope=.subtree
    task?.cancel(); engine.searchCancel(old_handle)
    phase=.running; results=[]; hitCount=0
    task = Task {
      sleep(200ms)
      handle = await engine.searchStart(new_root, "TODO", true, false)
        → FFI → Rust:
          NEXT_HANDLE.fetch_add(1) → 42
          session = Session::new(root, opts)
            spawn_thread: {
              walker = WalkBuilder::new(root).hidden(!hidden).build()
              for entry in walker:
                if cancel.load(): break
                if !name.to_lower().contains("todo"): continue
                buffer.push(FileEntry)
                matched += 1
                if matched >= 5000: status=Capped; cancel.set(true); break
                if buffer.len() >= 256: tx.send(batch)
              tx.send(remaining); drop(tx)
              status = Done or Capped
            }
          REGISTRY.lock().insert(42, session)
          return 42
      while batch = await engine.searchNextBatch(42) {
        MainActor:
          results += batch
          results.sort(by: currentSort)
          hitCount = results.count
          if results.count >= 5000: phase = .capped
      }
      MainActor: if phase == .running { phase = .done }
    }

ContentView entries = searchModel.results (isActive)
FileListView updateNSView → coordinator.applyModelSnapshot(entries, searchRoot: new_root)
NSTableView reloadData → Folder 컬럼 포함 row 렌더

유저가 결과에서 파일 우클릭 → coordinator.menu(for:) →
  기존 로직 그대로 (Reveal / Copy Path / Open With / Move to Trash)
  entry.path 는 full path 이므로 동작 정상
```

---

*이 문서는 `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md` § 11 M1.6 의 확장·구체화다. 구현 플랜은 `docs/superpowers/plans/YYYY-MM-DD-cairn-phase-1-m1.6-search-polish.md` 로 별도 작성 (superpowers:writing-plans).*
