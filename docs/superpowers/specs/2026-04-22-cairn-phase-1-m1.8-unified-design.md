# Cairn M1.8 — Unified Design · `v0.1.0-alpha.2`

> **Status:** Brainstorm complete (2026-04-22). Ready for `superpowers:writing-plans`.

**Goal.** M1.7 가 깔아놓은 visual 폴리시 위에서 Cairn 의 **primary interaction model** 을 Finder 에서 탈출해 `⌘K` palette 중심으로 뒤집는다. 동시에 M1.7 피드백의 UX 정리 (toolbar slim down, sidebar Finder parity, Glass 실제로 파랗게) 와 Phase 2 로 계획돼 있던 Rust foundation (`cairn-index`, FSEvents, git, content search, symbols) 을 한 마일스톤에 통합 전달.

**Scope 리스크 (명시).** 이 spec 은 단일 마일스톤으로는 이례적으로 크다 — 약 4–6 주, 중간 tag 없음. Phase 2 로 계획된 전체 Rust foundation (`cairn-index`, FSEvents, git, tree-sitter, ripgrep 통합) + UX 재구성 (palette, tabs, multi-window, sidebar parity, toolbar slim, git column) + bug fix (Glass, ⌘F) 를 전부 합친 규모. 단계 분해 옵션을 brainstorm 단계에서 제시했으나 사용자가 단일 M1.8 통합을 명시적으로 선택. Plan 작성 단계에서 task 가 20+ 개 나올 가능성 높으며, 각 task 에 spec/quality review checkpoint 를 추가해 중간 드리프트 방지. DoD 미충족 항목이 생기면 해당 sub-feature 만 다음 마일스톤으로 롤백하는 옵션 (기존 경로 — `cairn-index` / `@` symbol / AirDrop / Network 등이 후보) 도 명시적 fallback 으로 둔다.

**Architecture pivot.** 기존 "한 창 = 한 폴더" 모델을 **창 = N 탭, 탭 = 1 폴더 컨텍스트** 로 재구성. 각 탭이 자체 `FolderModel / SearchModel / PreviewModel + IndexHandle` 세트를 소유. `⌘K` palette 는 탭의 Index 를 쿼리하는 uniform surface.

**Tech Stack.** Swift 5.9 · SwiftUI · AppKit · macOS 14 · xcodegen 2.45 | Rust 1.85 · swift-bridge 0.1.59 · **redb 2.x (new)** · **notify 6.x / CFNotificationCenter (new)** · **git2 0.18 (new)** · **tree-sitter 0.22 + grammars: swift / typescript+tsx / python / rust (new, 5 grammars)** · ripgrep (번들된 `rg` 바이너리 spawn)

**App bundle 변경.** ripgrep 바이너리 (`rg`, universal binary ~5MB) 를 `Contents/Resources/rg` 로 번들. `project.yml` 에 Copy Files phase 추가. 런타임에 `Bundle.main.url(forResource: "rg", withExtension: nil)` 로 경로 확보 후 spawn.

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main, HEAD 시작 = `phase-1-m1.7` @ `40a39b2`)

**Predecessor:** `docs/superpowers/plans/2026-04-22-cairn-phase-1-m1.7-design-polish.md` (완료, tag `phase-1-m1.7` + `v0.1.0-alpha.1`)

**Deliverable verification (M1.8 완료 조건):**
- `cargo fmt --check` / `cargo clippy -D warnings` / `cargo test --workspace` 전부 green (신규 crate 2개 포함)
- `xcodebuild build` PASS, `xcodebuild test` **60+ tests** (M1.7 34 + 신규 palette query parser / index round-trip / git status / tree-sitter smoke / tab state)
- `build-rust.sh` + `gen-bindings.sh` 돌리면 **Generated diff 가 크게 생김 (예상됨, M1.7 의 "diff 0" 제약 해제)**
- 앱 실행 → Glass 파랗게, toolbar slim, tabs 동작, `⌘K` palette 5 모드, Git 컬럼, 확장된 사이드바, Favorites 자동 채움
- `git tag phase-1-m1.8` + `git tag v0.1.0-alpha.2` (같은 HEAD)

---

## 1. Brainstorm 결정 요약

brainstorm 세션 (2026-04-22) 에서 아래 선택:

| # | 질문 | 선택 |
|---|---|---|
| Q3 | 검색 스택 UX 경계 | **A** — ⌘K 하나로 통합 (primary interaction) |
| Q4 | Palette scope | **A** — 현재 탭의 폴더 subtree 만 |
| Q5 | Multi-pane | **B+D** — Tabs + 새 창 (split 은 Phase 3) |
| Q6 | 사이드바 섹션 | **Group 1+2** — Favorites / Home / AirDrop / Trash / Network |
| Q7 | Git 표시 | **A** — 파일 리스트 Git 컬럼 + 사이드바 branch/dirty 뱃지 |
| Q8 | Glass 톤 | **B** — `.sidebar` material + 파랑 tint opacity ~0.25 |
| Q9 | Toolbar + tabs 레이아웃 | **A** — Tab bar 별도 줄, breadcrumb nav 옆 |
| Q10 | Palette 위치/prefix | 중앙 floating, prefix 5개 전부 (none / > / / / # / @) |
| Q11-1 | ⌘F 동작 | **B** — palette 열고 fuzzy 모드 pre-focus |
| Q11-2 | 탭 키 매핑 | 표준 (⌘T 복제 / ⌘W / ⌘1-9 / ⌘⌥←→) |
| Q11-3 | Preview pane | **A** — 탭별 |
| Q11-4 | Content 스크롤 + Git granularity | 둘 다 **A** (line 스크롤, 단순 status) |

---

## 2. Architecture

### 2.1 Rust 레이어 (신규)

#### `crates/cairn-index/` — Persistent file index
- Backend: **redb 2.x** (zero-copy, embedded, no background server)
- 저장 위치: `~/Library/Caches/Cairn/index/<path-sha256>.redb` (path = 캐노니컬화된 폴더 root)
- 테이블:
  - `files(path_rel: String) -> FileRow { size, mtime, kind, git_status, symbol_count }`
  - `symbols(file_rel: String, idx: u32) -> SymbolRow { name, kind, line, col }`
  - `meta() -> IndexMeta { version, root_path, last_walk_at, walker_commit }`
- **Content 는 pre-index 하지 않음** — ripgrep spawn-per-query 방식. Index 는 metadata + symbols 만.
- 생명주기:
  - `index_open(root)` — 캐시 있으면 로드, 없으면 비어있는 redb 생성
  - 최초 방문 시 `walk_and_populate()` 백그라운드 (`CairnEngine` 의 기존 walker 재사용, symbol extractor + git annotator 붙임)
  - FSEvents 이벤트 도착마다 `apply_delta(events)` 호출 (INCR 업데이트)
  - `index_close()` — watch 해제 + redb flush
- **소비자 API (sync, 빠름 → FFI 직노출)**:
  - `query_fuzzy(handle, query: &str, limit: u32) -> Vec<FileHit>` (nucleo 크레이트)
  - `query_git_dirty(handle) -> Vec<FileHit>`
  - `query_symbols(handle, query: &str, limit: u32) -> Vec<SymbolHit>`
- **소비자 API (streaming, 느림 → FFI 는 채널/포인터)**:
  - `query_content(handle, pattern: &str) -> ContentStream` (ripgrep spawn, stdout 파싱)

#### `crates/cairn-git/` — Git status/branch
- Backend: **git2 0.18** (libgit2 래퍼)
- `git_branch(path: &Path) -> Option<String>`
- `git_status_snapshot(path: &Path) -> GitSnapshot { branch, modified: Vec<PathBuf>, added, deleted, untracked }`
- index walker 가 파일별 status 를 snapshot 에서 조회 → `FileRow.git_status` 채움
- Stateless (매번 repo open/close, libgit2 internal cache 에 의존) — 최적화는 M2.x

#### `crates/cairn-ffi/` (기존) — swift-bridge 확장
- `IndexHandle` opaque type export
- Index open/close/query 함수 bridge
- `GitSnapshot` struct bridge (값 타입)
- `ContentStream` 은 swift-bridge 가 Rust → Swift 스트림 지원 제한적이라, **콜백 기반** 으로 구현: `query_content(handle, pattern, callback)` — callback 은 `(ContentHit) -> Void`, Rust 쪽에서 spawn 한 스레드가 콜백을 main actor 에 dispatch 할 수 있게 `@Sendable` 처리.

### 2.2 Swift 레이어 (신규 + 수정)

#### 신규 ViewModel / Service
- `IndexService` — `IndexHandle` 래퍼. 탭별 1 instance. lifecycle = 탭 lifetime.
- `GitService` — `GitSnapshot` poll wrapper. 폴더 변경 시 refresh.
- `CommandPaletteModel` — palette 상태 (query string, 현재 mode, results, selected row, streaming 상태)
- `WindowSceneModel` — 창 단위 state: `tabs: [Tab]`, `activeTabID: Tab.ID`
- `Tab` — `{ id: UUID, folder: FolderModel, search: SearchModel, preview: PreviewModel, index: IndexService, git: GitService }`

#### 신규 View
- `CommandPaletteView` — 중앙 floating 640×400 overlay, `@Observable` 바인딩으로 CommandPaletteModel
- `PaletteRow` — mode-specific row renderer (`FileHit / CommandHit / ContentHit / GitHit / SymbolHit` 각각)
- `PaletteModeIndicator` — 왼쪽 작은 뱃지 (`>` = 커맨드, `/` = 내용, etc.)
- `TabBarView` — SwiftUI HStack 기반 탭 bar, drag-reorder (M2.x), close button, `+` 새 탭 버튼
- `TabChip` — 개별 탭 chip (폴더명, 닫기 x, 활성 highlight)
- `SidebarFavoritesSection` — 기본 4개 + 사용자 Pin 합쳐 렌더링
- `GitBranchFooter` — 사이드바 하단, 현재 탭 repo 이면 branch 뱃지

#### 수정
- `CairnApp.swift` — window material `.sidebar` 로, `WindowGroup` 에 `CommandGroup` + `CommandMenu` 등록 (⌘F, ⌘T, ⌘W, ⌘1..9, ⌘N, ⌘K 등)
- `CairnTheme.swift` — `panelTint` 재조정, `windowMaterial` 토큰 교체
- `ContentView.swift` — `WindowSceneModel` 주입, 탭 라우팅, `contentColumn` 이 활성 탭의 `Tab` 을 읽음, palette overlay 얹음
- `SidebarView.swift` — 섹션 재구성 (Favorites auto + Recent + Cloud + Locations 확장)
- `FileListView.swift` — Git 컬럼 추가
- `FileListCoordinator.swift` — Git 컬럼 데이터 바인딩 (`tab.git.statusFor(path)`)
- `AppModel.swift` — `currentTab` accessor 편의, 기존 `currentFolder` 는 `currentTab.folder.url` 로 위임
- `NavigationHistory.swift` — 탭별 history 분리 (기존 single → per-Tab)

---

## 3. UX Spec per Feature

### 3.1 Glass Blue fix
- `CairnApp.swift` 의 `.background(VisualEffectBlur(material: .hudWindow))` → `.background(VisualEffectBlur(material: .sidebar))`
- `CairnTheme.glass.panelTint = Color(hue: 0.60, saturation: 0.45, brightness: 0.55, opacity: 0.25)` — 실제 파란 hue
- `ContentView.fileList(...)` 의 `.background` 에서 `theme.panelTint.opacity(0.55)` → `.opacity(1.0)` (panelTint 자체에 이미 opacity 포함)
- 라이트 모드 체크 (Phase 3 theme variant 범위 전까지 컨트라스트 ratio 수동 검증)

### 3.2 Toolbar & Breadcrumb
```
┌─ToolBar (SwiftUI .toolbar)────────────────────────────────┐
│ [←] [→] [↑]  [Users › cyj › Docs]           [⌘K]          │
└───────────────────────────────────────────────────────────┘
┌─Tab Bar (TabBarView)──────────────────────────────────────┐
│ [📁 Docs ×] [📁 Downloads ×] [+]                          │
└───────────────────────────────────────────────────────────┘
```
- `ToolbarItemGroup(placement: .navigation)`: back, forward, up, **breadcrumb** (기존 `.principal` 에서 이동)
- `ToolbarItem(placement: .primaryAction)`: `⌘K` 힌트 버튼 — 작은 chip 모양에 "⌘K Search" 글자, 클릭 = palette 열기
- Pin / eye / reload 버튼 전부 제거. 대응 단축키는 `.commands` CommandMenu 로만 살림:
  - Commands 메뉴에 "Toggle Hidden Files" `⌘⇧.` / "Reload" `⌘R` / "Pin Current Folder" `⌘D`
  - 팔레트 `>` 모드에도 같은 명령 노출 (UI 없어도 접근 가능)
- SearchField 토크바 아이템 제거 (컴포넌트 파일 `ThemedSearchField.swift` 는 **삭제**)
- Scope picker (This Folder / Subtree) — subtree 를 유일 기본으로, picker UI 제거 (SearchModel 의 scope 필드 자체는 남기되 기본값 `.subtree` 로 고정, 코드 내 분기 간소화)

### 3.3 Tabs + Multi-window
- `WindowGroup` 안에 `WindowSceneModel` 주입. SwiftUI `@State` 로 윈도우 단위 life.
- 탭 생성/삭제/순서는 `WindowSceneModel` 에서 관리. 활성 탭 전환 시 `ContentView` 는 `activeTab` 의 state 를 구독.
- 단축키 (`.commands` CommandGroup):
  - `⌘T` → `scene.newTab(cloning: activeTab)` (폴더 복제)
  - `⌘W` → `scene.closeTab(activeTab)`; 탭이 마지막이면 `NSApp.keyWindow?.close()`
  - `⌘1..⌘9` → `scene.activateTab(at: n-1)`
  - `⌘⌥←` / `⌘⌥→` → prev / next
  - `⌘N` → 기본 WindowGroup 새 창 (SwiftUI 기본 동작)
- **Session restore / pinned tabs = M2.x 명시 제외**
- Tab chip UI: 폴더 lastPathComponent + `×` (hover 시 보임) + 활성 탭은 `theme.accentMuted` 배경

### 3.4 Sidebar — Finder parity
```swift
Section("Favorites") {
    // Auto (항상 첫 4 개, 사용자가 unpinned 해도 유지)
    AutoFavorite("Applications", icon: "app.badge", url: /Applications)
    AutoFavorite("Desktop",      icon: "menubar.dock.rectangle", url: ~/Desktop)
    AutoFavorite("Documents",    icon: "doc",                    url: ~/Documents)
    AutoFavorite("Downloads",    icon: "arrow.down.circle",      url: ~/Downloads)
    // 사용자 Pin (기존 BookmarkStore.pinned)
    ForEach(app.bookmarks.pinned) { PinnedRow($0) }
}

Section("Recent") { /* 기존 그대로 */ }

Section("Cloud") {                 // rename from "iCloud"
    if let iCloud = sidebar.iCloudURL { /* iCloud Drive row */ }
    // Phase 2+ 로 Dropbox/Drive 감지 확장 여지
}

Section("Locations") {
    HomeRow(url: ~/\(NSUserName()))          // NEW
    ForEach(sidebar.locations) { LocationRow($0) }  // 기존 / + 마운트
    AirDropRow()                             // NEW — Finder 의 AirDrop 창 open
    NetworkRow(url: /Network)                // NEW
    TrashRow()                               // NEW — ~/.Trash 탐색 + "Empty" 컨텍스트
}

// Optional footer: repo branch badge
if let snap = activeTab.git.snapshot {
    GitBranchFooter(branch: snap.branch, dirtyCount: snap.modified.count + snap.untracked.count)
}
```

AutoFavorite 는 BookmarkStore 와 독립. 사용자 Pin 삭제/추가는 기존 API 그대로, 단지 sidebar section label 만 "Pinned" → "Favorites" 로 변경 후 자동 4개 앞에 붙임.

AirDrop: macOS 가 **외부 앱에서 AirDrop 창을 띄우는 공식 API 를 노출하지 않음**. 대안:
- 파일리스트 selection 이 있으면 → `NSSharingService(named: .sendViaAirDrop)` 로 해당 파일들을 AirDrop share 패널 열기
- Selection 이 없으면 → 작은 toast / 알림 "Select files first, then click AirDrop"
- 따라서 이 row 는 "AirDrop" 인데 실제로는 "선택 파일을 AirDrop 으로 보내기" 쇼트컷. UI 라벨은 `"AirDrop"` 유지, hover tooltip 으로 동작 설명.
- 이 제약 spec §9 (Out of scope) 의 반대편 — 정확히 "Finder 처럼 되지 않는" 지점이므로 DoD 체크리스트에서 "selection-기반 AirDrop 패널 열림" 으로 명시.

Trash: 클릭 시 `~/.Trash` 로 navigate. Row 컨텍스트메뉴에 "Empty Trash" → `NSFileManager` 로 삭제 + 확인 alert.

### 3.5 Command Palette (`⌘K`)
**위치/크기**: 창 중앙 640×400 floating overlay. 배경 dim `Color.black.opacity(0.35)`. ESC 또는 창 밖 클릭 = 닫힘.

**구조**:
```
┌─────────────────────────────────────────────────────────┐
│  [>] ›  new t|                                          │ ← mode indicator + query input
├─────────────────────────────────────────────────────────┤
│  ⚡  New Tab                               ⌘T           │ ← highlighted (selected)
│  🔄  Reload                                ⌘R           │
│  👁   Toggle Hidden Files                   ⌘⇧.          │
│  📌  Pin Current Folder                    ⌘D           │
│  ...                                                    │
└─────────────────────────────────────────────────────────┘
```

**Input parser** (`CommandPaletteModel.parse(_ raw: String) -> ParsedQuery`):
- 빈 문자열 → `.fuzzy("")`
- `>xxx` → `.command("xxx")`
- `/xxx` → `.content("xxx")`
- `#xxx` → `.gitDirty("xxx")` (xxx 로 추가 filter)
- `@xxx` → `.symbol("xxx")`
- 그 외 → `.fuzzy(raw)`

**Mode dispatch**:
| Mode | Source | Streaming? | Row renderer |
|---|---|---|---|
| fuzzy | `IndexService.queryFuzzy(query)` | no (sync) | icon + name + 회색 상대경로 |
| command | built-in 커맨드 리스트 + nucleo rank | no | SF Symbol + label + 단축키 chip |
| content | `IndexService.queryContent(pattern, callback)` | yes (spawn ripgrep) | 파일 아이콘 + 파일명 + 매치 line preview (회색) |
| gitDirty | `IndexService.queryGitDirty` + nucleo filter | no | Git status chip + 파일명 + 경로 |
| symbol | `IndexService.querySymbols` | no | kind icon + symbol 이름 + 파일:line hint |

**선택/활성화**:
- `↑` / `↓` → 이동
- `⏎` → 기본 액션 (파일/폴더: 열기 · 커맨드: 실행 · 내용: 파일 열고 line 스크롤 · git: 파일 열기 · 심볼: 파일 열고 line 스크롤)
- `⌘⏎` → 보조 액션 (파일: Reveal in Finder · 커맨드: n/a · 기타: 보조 없음)
- `⌘C` → 결과 경로 클립보드 (파일/폴더 대상)

**퍼지 매칭**: `nucleo` 크레이트 (Rust), FFI 로 노출. Swift 쪽은 glob highlight index 를 받아 AttributedString 렌더링.

**⌘F 별칭**: `⌘F` → palette 열기 + 모드 미리 fuzzy 로 (query 입력창 empty, placeholder "Find files…"). `⌘K` 는 palette 열기 (빈 상태). 기능상 동일, placeholder 메시지만 다름 (muscle memory).

**콜백 기반 content 스트리밍**:
- Palette 가 `/xxx` 쿼리를 parse 하면 `IndexService.queryContent(pattern)` 호출
- Rust 쪽에서 별도 스레드가 ripgrep 자식 프로세스 spawn → stdout 파싱 → 매 hit 마다 Swift callback 호출 (main actor hop)
- Swift 는 `@Published results: [ContentHit]` 에 append, SwiftUI List 가 즉시 반영
- Query 변경 시 이전 쿼리의 child process SIGTERM + 버퍼 초기화
- 디바운스: 80ms (type 속도 고려)

### 3.6 Git awareness
- File list 에 `Git` 컬럼 (identifier `.git`) 추가:
  - repo 안 폴더면 보임 (width 48, min 32), 아니면 hidden
  - 값: `—` / `M` / `A` / `D` / `??` (tinted — modified yellow, added green, deleted red, untracked gray)
  - sortDescriptor 지원: "dirty first" 정렬 가능
- 사이드바 footer `GitBranchFooter`:
  - 현재 탭 폴더가 `cairn-git::repo_root()` 반환하면 표시
  - 포맷: `main • 3` (branch 이름 + modified+untracked 합)
  - 클릭 = no-op (M2.x 에서 GitHub Desktop-like 패널 가능성)
- `IndexService` 가 `GitService` 를 의존 — index walker 가 파일별 status 를 FileRow 에 채움. 갱신: FSEvents 이벤트에서 `.git/HEAD` 또는 `.git/index` 변경 감지 시 전체 snapshot refresh.

### 3.7 Keyboard map (전체)
| Shortcut | Action |
|---|---|
| `⌘K` | Palette 열기 (빈 상태) |
| `⌘F` | Palette 열기 (fuzzy placeholder) |
| `⌘T` | 새 탭 (현재 폴더 복제) |
| `⌘W` | 탭 닫기 (마지막이면 창 닫기) |
| `⌘1..⌘9` | n 번째 탭 활성화 |
| `⌘⌥←` / `⌘⌥→` | 이전 / 다음 탭 |
| `⌘N` | 새 창 |
| `⌘←` / `⌘→` | 탭 내 history back / forward |
| `⌘↑` | 부모 폴더 |
| `⌘R` | 현재 폴더 reload (커맨드 메뉴 + palette `>reload`) |
| `⌘D` | Pin/Unpin 현재 폴더 |
| `⌘⇧.` | 숨김 파일 토글 |
| `Space` | QuickLook (기존) |
| `⏎` | 파일 열기 / 폴더 진입 (기존) |
| `⌘⏎` (파일리스트 내) | Reveal in Finder |
| `⌘⌥C` | Copy Path (기존) |
| `⌘⌫` | 휴지통 (기존) |
| `ESC` | Palette 닫기 |

---

## 4. Data flow diagrams

### 4.1 Index lifecycle (per-tab)
```
User navigates to /Users/cyj/proj
 → ContentView dispatches to activeTab
 → Tab.index = IndexService(root: /Users/cyj/proj)
 → IndexService.open():
     1. hash(root) = abc123...
     2. cachePath = ~/Library/Caches/Cairn/index/abc123.redb
     3. If exists → load redb; else create empty + trigger walk
     4. Start FSWatcher(root) → IndexService.applyDelta(_)
     5. Start GitService.snapshotLoop(root) (debounced refresh every 2s while active)
 → Palette queries route through IndexService

User navigates away (same tab, different folder)
 → Tab.index.close() (flush redb, stop watch, stop git loop)
 → New IndexService for new root

User closes tab
 → Same as above + remove Tab from WindowSceneModel.tabs
```

### 4.2 Palette query flow
```
User types "myclass" in palette
 → CommandPaletteModel.queryDidChange("myclass")
 → parse → .fuzzy("myclass")
 → debounce 40ms
 → activeTab.index.queryFuzzy("myclass", limit: 50)
 → IndexService (Swift) → ffi_index_query_fuzzy (Rust)
 → redb scan + nucleo rank
 → Vec<FileHit> returned sync
 → CommandPaletteModel.results = hits
 → SwiftUI List 렌더
```

### 4.3 Content search flow (streaming)
```
User types "/class FileList" in palette
 → parse → .content("class FileList")
 → debounce 80ms
 → activeTab.index.queryContent(pattern, callback: appendHit)
 → IndexService spawns Task → ffi_index_query_content_async
 → Rust 쪽 thread spawns rg --json pattern <root>
 → stdout line-by-line parse → JSON → ContentHit
 → per-hit: callback(hit) (Swift closure, scheduled on @MainActor)
 → CommandPaletteModel.results.append(hit)
 → SwiftUI List 즉시 반영

User types new char → cancel previous query (SIGTERM rg child, clear results, restart)
```

---

## 5. Tests (추가 25 개 목표)

### Rust (`cargo test --workspace`)
- `cairn-index::tests::index_roundtrip` — 임시 폴더에 파일 3 개 두고 walk → redb 저장 → 다시 open → 동일 결과
- `cairn-index::tests::fuzzy_query_ranks_substring` — "foo" 검색에 "foo.txt" > "barfoo.txt" 순서
- `cairn-index::tests::apply_delta_insert` — FSEvents delta 시뮬 이벤트로 new file 등록
- `cairn-index::tests::apply_delta_delete` — 파일 삭제 delta → FileRow 제거
- `cairn-index::tests::symbols_swift_basic` — Swift 스니펫에 `class Foo { func bar() {} }` → 2 symbols 추출
- `cairn-index::tests::symbols_multi_lang` — 4 언어 각 1 파일 smoke
- `cairn-git::tests::status_modified_file` — 임시 repo 생성, 파일 수정, snapshot 에 포함 확인
- `cairn-git::tests::branch_name` — feature/xxx 브랜치 만들고 반환
- `cairn-git::tests::not_a_repo` — non-repo 폴더 → `None`

### Swift (`xcodebuild test`)
- `CommandPaletteModelTests` (6 개)
  - `parse_empty` / `parse_fuzzy` / `parse_command` / `parse_content` / `parse_gitDirty` / `parse_symbol`
- `TabTests` (3 개)
  - `duplicate_tab_carries_folder_url`
  - `close_last_tab_closes_window`
  - `activate_tab_by_index`
- `WindowSceneModelTests` (2 개)
  - `new_tab_appended_and_active`
  - `close_tab_picks_prev_active`
- `IndexServiceTests` (3 개)
  - `open_reopen_same_folder_uses_cache`
  - `query_fuzzy_returns_hits`
  - `query_content_streams_hits`
- `GitServiceTests` (2 개)
  - `snapshot_returns_branch`
  - `snapshot_caches_between_polls`
- `SidebarViewTests` (2 개)
  - `favorites_auto_entries_present_without_pins`
  - `git_footer_shown_when_repo`

### 총 테스트 수
M1.7 34 + Rust 9 + Swift 18 = **61** (목표 60+ 달성)

---

## 6. File structure

### 신규 Swift
```
apps/Sources/Views/Palette/
  CommandPaletteView.swift
  PaletteRow.swift
  PaletteModeIndicator.swift
apps/Sources/ViewModels/
  CommandPaletteModel.swift
  Tab.swift
  WindowSceneModel.swift
apps/Sources/Views/Tabs/
  TabBarView.swift
  TabChip.swift
apps/Sources/Views/Sidebar/
  SidebarFavoritesSection.swift
  GitBranchFooter.swift
  SidebarAutoFavoriteRow.swift
apps/Sources/Services/
  IndexService.swift
  GitService.swift
apps/CairnTests/
  CommandPaletteModelTests.swift
  TabTests.swift
  WindowSceneModelTests.swift
  IndexServiceTests.swift
  GitServiceTests.swift
  SidebarViewTests.swift
```

### 신규 Rust
```
crates/cairn-index/
  Cargo.toml
  src/
    lib.rs          (public API + IndexHandle)
    store.rs        (redb schema + open/load/flush)
    walker.rs       (walk + FileRow 생성, 기존 cairn-engine walker 재사용)
    symbols.rs      (tree-sitter adapter, 4 언어 grammar 삽입)
    content.rs      (ripgrep spawn + JSON parse)
    fuzzy.rs        (nucleo 래퍼)
    watch.rs        (notify/CFNotification 래퍼, apply_delta 생성)
    tests/
      roundtrip.rs
      fuzzy.rs
      symbols.rs
      delta.rs
crates/cairn-git/
  Cargo.toml
  src/
    lib.rs
    snapshot.rs
    tests.rs
crates/cairn-ffi/src/
  index.rs          (IndexHandle + 쿼리 함수 bridge)
  git.rs            (GitSnapshot bridge)
  content.rs        (content search callback bridge)
```

### 수정
```
apps/Sources/CairnApp.swift              (window material, CommandGroup, CommandMenu)
apps/Sources/Theme/CairnTheme.swift      (panelTint 재조정)
apps/Sources/ContentView.swift           (toolbar 재구성, palette overlay, activeTab 라우팅)
apps/Sources/Views/Sidebar/SidebarView.swift  (섹션 재구성)
apps/Sources/Views/FileList/FileListView.swift        (Git 컬럼)
apps/Sources/Views/FileList/FileListCoordinator.swift (Git 컬럼 바인딩)
apps/Sources/App/AppModel.swift          (탭 경유 access helper)
apps/Sources/ViewModels/NavigationHistory.swift       (탭별 history)
apps/Sources/Views/Search/ThemedSearchField.swift     (삭제 — palette 로 대체)
crates/cairn-ffi/Cargo.toml              (deps: cairn-index, cairn-git)
crates/cairn-ffi/build.rs                (bridge regeneration)
apps/project.yml                         (신규 디렉터리 glob 확인)
```

---

## 7. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| **swift-bridge 로 Rust → Swift 콜백 복잡** (content streaming) | 중 | 타입 minimize: `query_content(pattern, on_hit, on_done)` 두 콜백만. 에러는 on_done 에 Result. 테스트에서 mock callback. |
| **tree-sitter grammar 4개 빌드 시간** | 중 | 빌드 캐시 + CI 병렬. 로컬 첫 빌드 5–10분 예상. |
| **redb lock contention** (다중 탭이 같은 루트 열면) | 낮음 | IndexService layer 에서 root path dedupe — 같은 루트 2 탭이면 IndexService 공유 (refcount). close 는 마지막 참조자만. |
| **FSEvents 이벤트 폭발** (대형 폴더 대량 변경) | 중 | `notify` debounce 100ms + batch. index 재빌드는 1000+ 이벤트 임계값 넘으면. |
| **Glass Blue 라이트 모드에서 text 깨짐** | 중 | Phase 3 theme variant 전까지 밝기 조절. WCAG AA (4.5:1) 체크 후 필요 시 `@Environment(\.colorScheme)` 조건 분기 추가. |
| **탭 state memory** (탭 N 개 × IndexHandle) | 중 | IndexService 에 LRU cap (열린 탭 수 + 최근 5 = 최대 N+5 handle). 초과 시 redb close (캐시 유지). |
| **ripgrep 미설치 환경** | 높음 | M1.8 은 ripgrep 을 **번들** (앱 번들 `Contents/Resources/rg` 에 포함). 설치 감지 안 하고 번들 우선. |
| **Scope 기간 초과** | 높음 | 주 단위 WIP 커밋 + 중간 self-review. 각 task 간 의존성 그래프 사전 점검. 문제 시 일부 feature descope (예: `@` 심볼 → M2.x). |

---

## 8. Migration notes (from M1.7)

- `SearchModel` 의 `scope` 필드는 유지 (API 호환) 하되 기본값 `.subtree`, picker UI 삭제. Phase 2+ 에서 다시 분기 검색 필요해지면 UI 복귀 가능.
- 기존 `ThemedSearchField` 는 삭제. 삭제 후 `ContentView` 의 toolbar 에서 참조 제거.
- `AppModel.currentFolder` 는 **여러 창 × 여러 탭** 환경에서 ambiguous 해짐. 해결:
  - `AppModel` 에서 제거 (현재 @Observable 은 창 전역 싱글톤이라 탭 개념 수용 못 함).
  - 새 `WindowSceneModel.activeTab.folder.url` 가 진실. 기존 `AppModel` 소비자 (SidebarView / BreadcrumbBar / AppModel 내부) 는 `@Environment` 경유로 `WindowSceneModel` 주입받아 리팩터.
  - `AppModel.navigate(to:)` / `goBack()` / `goUp()` 등 탭-specific 동작은 `WindowSceneModel.activeTab.history` 로 위임.
  - 리팩터 범위 명시: sidebar (13 개 call site), breadcrumb (3), contentView (6), AppModel 내부 (goBack/forward/goUp/toggleShowHidden/navigate). 총 ~30 곳. 각 plan task 에 분산.
- `BookmarkStore` 는 Favorites section 의 사용자 Pin 부분에만 연결. Auto Favorites 는 별도 컴포넌트로 BookmarkStore 와 무관.
- M1.7 의 `FileListIconCache` 는 그대로 사용. Tab 당 별도 인스턴스 유지 (Tab init 에서 생성).

---

## 9. Out of scope (명시 미뤘음)

- Split pane (좌우 나란히 보기) → Phase 3
- Pinned tabs / session restore → M2.x
- Tag 통합 (macOS Finder tags) → M2.x
- Shared / Dropbox·Drive 감지 → M2.x
- Theme switcher UI → Phase 3
- Light mode CairnTheme variant (text tokens 재조정) → Phase 3
- Git: staged vs worktree 분리, diff viewer → M2.x
- Smart folders → Phase 3
- `@` 심볼 파서 추가 언어 (Go / Kotlin / Ruby …) → M2.x
- Content 결과에 inline replace → Phase 3
- Drag & drop 파일 이동 → M2.x

---

## 10. Definition of Done

- [ ] Rust: `cairn-index` + `cairn-git` crate 신규, `cargo fmt / clippy / test --workspace` green
- [ ] FFI: swift-bridge 재생성 후 Generated 파일 커밋 (diff 있음, 정상)
- [ ] Swift: 신규 ViewModel / View / Service 모듈 전부 존재, `xcodebuild build` 성공
- [ ] `xcodebuild test` **60 + tests** green
- [ ] 앱 실행 시:
  - Glass 배경 실제로 파랗게 (다크/라이트 모두 인지 가능)
  - Toolbar 에 back/forward/up + breadcrumb + `⌘K` chip (나머지 버튼 없음)
  - Tab bar 표시, `⌘T` / `⌘W` / `⌘1..9` / `⌘⌥←→` 동작
  - `⌘N` 새 창 동작
  - `⌘K` / `⌘F` palette 열림, 5 prefix 모두 동작 (none / > / / / # / @)
  - Content 결과 클릭 → 파일 열기 + 매치 line 스크롤 확인
  - Sidebar: Favorites 자동 4개 + Home + AirDrop + Trash + Network 전부 렌더링
  - Git 컬럼 표시 (repo 안 폴더), 사이드바 footer 에 branch + dirty count
- [ ] FSEvents: 외부 터미널에서 파일 추가/삭제 하면 Cairn 파일 리스트 즉시 반영
- [ ] Ripgrep 번들 포함, 외부 설치 의존 없음
- [ ] 라이트 모드 WCAG AA 체크 (맞지 않으면 Phase 3 notes 에 명시)
- [ ] `git tag phase-1-m1.8` + `git tag v0.1.0-alpha.2` (같은 HEAD)

---

## 11. 다음 단계

1. 이 spec 을 `main` 에 커밋 (`docs(spec): add M1.8 unified design for v0.1.0-alpha.2`)
2. `superpowers:writing-plans` skill 호출 → 이 spec 을 기반으로 세부 task-by-task 구현 plan 작성
3. Plan 완성 후 `superpowers:subagent-driven-development` 로 실행
4. 각 task 후 spec/quality review checkpoint (M1.7 과 동일 패턴)
