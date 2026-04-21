# Cairn Phase 1 — Design Spec

**Date:** 2026-04-21
**Author:** ongjin (with Claude)
**Status:** Approved (브레인스토밍 결과, writing-plans 인풋)
**Parent spec:** [`2026-04-21-cairn-design.md`](./2026-04-21-cairn-design.md)
**Predecessor:** [`2026-04-21-cairn-phase-0-foundation.md`](../plans/2026-04-21-cairn-phase-0-foundation.md) (완료)

---

## 1. 목표

Phase 0에서 검증된 Rust ↔ Swift 파이프라인 위에, **3개월 안에 "눈 찡그리면 데일리 드라이버가 될 법한" 로컬 파일 매니저**를 올린다. Finder 대체까진 아님 — 핵심 탐색·프리뷰·사이드바가 제대로 도는 v0.1.0-alpha 릴리즈가 끝.

성공 기준 1줄: **"⌘O 로 폴더 열고 → 사이드바/브레드크럼/파일 리스트/프리뷰로 탐색만 해서 일상 업무 10분 버틸 수 있다."**

## 2. 범위 (Locked)

### 2.1 들어가는 것

- **Rust 엔진**: `cairn-walker`(FS 순회 + .gitignore) + `cairn-preview`(텍스트 프리뷰 첫 2KB)
- **Swift 앱**:
  - three-pane 레이아웃 (NavigationSplitView)
  - **NSTableView 기반** 파일 리스트 (컬럼 3개, 정렬, 다중 선택, 컨텍스트 메뉴)
  - 사이드바 (Pinned / Recent / Devices)
  - 프리뷰 패널 (텍스트 2KB + 이미지 256px 썸네일 + 메타)
  - 브레드크럼 바 (세그먼트 클릭 네비)
  - Theme B · **Glass Blue** V1 팔레트 (인스턴스 1개)
  - Quick Look (`Space` → QLPreviewPanel)
  - 컨텍스트 메뉴 (Reveal in Finder / Copy Path / Move to Trash)
- **권한 모델**: **macOS 샌드박스 ON** · `files.user-selected.read-write` · security-scoped bookmarks
- **키보드**: `⌘↑` / `⌘←→` / `⌘D` / `⌘R` / `⌘⇧.` / `Space` / `⌘O` / `⌘N`

### 2.2 안 들어가는 것 (Phase 2+)

- 검색 (⌘K 팔레트, Deep search) — **Phase 2**
- FSEvents 실시간 갱신 — **Phase 2** (Phase 1은 수동 `⌘R`)
- 인덱스 캐시 (`cairn-index` redb) — **Phase 2**
- Theme A (Arc), Theme C (Raycast), 테마 스위처, Settings UI — **Phase 3**
- 드래그 & 드롭, 복사/붙여넣기, 리네임 — **Phase 4**
- Git status 오버레이, Finder Sync Extension — **v1.1**
- App Store 등록 (샌드박스 기반은 잡혀있지만 notarize/provisioning은 Phase 5)
- **Settings 윈도우는 의도적으로 Phase 1 밖** — Phase 1에 설정할 의미 있는 항목이 "show-hidden 기본값" 정도뿐이고(런타임 `⌘⇧.` 로 이미 토글 가능), "Indexed Roots" 는 Phase 2 에 인덱스가 생겨야 의미를 갖는다. 테마 스위처는 Phase 3. Settings scene 자리만 `CairnApp` 에 reserved, 실제 UI는 Phase 2/3에.

## 3. 아키텍처

### 3.1 레이어 다이어그램

```
┌───────────────────────────────────────────────────────────┐
│ SwiftUI App  (apps/Cairn/)                                │
│                                                            │
│  Views ── NavigationSplitView (three-pane)                │
│    ├─ SidebarView  (List + 3 Sections)                    │
│    ├─ FileListView (NSTableView NSViewRep + 컬럼 3)       │
│    └─ PreviewPaneView (텍스트 · 이미지 · 메타 분기)       │
│                                                            │
│  ViewModels ─ @Observable                                  │
│    ├─ AppModel          (currentFolder URL, history)      │
│    ├─ FolderModel       (entries, sort, selection)        │
│    ├─ SidebarModel      (pinned/recent/devices)           │
│    └─ PreviewModel      (현재 선택 파일 프리뷰 캐시)      │
│                                                            │
│  Services                                                  │
│    ├─ CairnEngine       (Rust FFI 래퍼)                   │
│    ├─ BookmarkStore     (security-scoped bookmark)        │
│    └─ MountObserver     (NSWorkspace 알림)                │
│                                                            │
│  Theme                                                     │
│    └─ CairnTheme.glass  (V1 Glass Blue tokens)            │
└────────────────────┬──────────────────────────────────────┘
                     │ swift-bridge (cairn-ffi)
┌────────────────────▼──────────────────────────────────────┐
│ Rust Engine (crates/)                                     │
│                                                            │
│  cairn-core     (Engine 오케스트레이션)                   │
│  cairn-walker   (ignore + jwalk, gitignore, 메타)         │
│  cairn-preview  (텍스트 첫 2KB만)                         │
│  cairn-ffi      (bridge 정의 — greet() 제거, 실제 API)    │
│                                                            │
│  cairn-search / cairn-index — Phase 2 구현. 지금은 skel  │
└───────────────────────────────────────────────────────────┘
```

### 3.2 FFI 경계 원칙 (spec § 9.4 재확인)

1. **Narrow boundary** — 함수 개수 최소화
2. **Rust 상태 없음** — SwiftUI `@Observable` 은 Swift만 소유
3. **비동기는 Swift 쪽** — 모든 Rust 호출은 `Task.detached` 래핑

## 4. Rust 크레이트 API

### 4.1 `cairn-walker` (신규 구현)

```rust
pub struct WalkerConfig {
    pub show_hidden: bool,
    pub respect_gitignore: bool,
    pub exclude_patterns: Vec<String>, // 하드코딩: .git, node_modules, target, .next, build, dist
}

pub fn list_directory(
    path: &Path,
    config: &WalkerConfig,
) -> Result<Vec<FileEntry>, WalkerError>;

pub struct FileEntry {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,            // Directory 는 0
    pub modified_unix: i64,
    pub kind: FileKind,
    pub is_hidden: bool,
    pub icon_kind: IconKind,
}

pub enum FileKind { Directory, Regular, Symlink }

pub enum IconKind {
    Folder,
    GenericFile,
    ExtensionHint(String),    // "swift", "rs", "md" 등 — Swift가 NSWorkspace.icon(forFileType:) 호출
}

pub enum WalkerError {
    PermissionDenied,
    NotFound,
    NotDirectory,
    Io(String),
}
```

**의존성:**
- `ignore = "0.4"` — .gitignore 매처
- `jwalk = "0.8"` — 병렬 FS 순회 (Phase 2 Deep search 재사용)

**동작 규칙:**
- symlink 는 target 해석 없이 `Symlink` 로 표시. Phase 2에 해결 옵션.
- `.DS_Store` 는 항상 제외 (hidden 토글과 무관).
- 하드코딩 제외 목록은 `config.respect_gitignore = true` 일 때만 적용. 유저가 명시적으로 진입하면 (예: `node_modules` 사이드바 pin) 예외 허용은 Phase 2.
- **개별 엔트리의 `metadata()` 실패는 fatal 이 아님** — 해당 엔트리를 `size=0, modified_unix=0, kind=Regular` 로 채우고 순회는 계속. 폴더 전체 `list_directory` 가 `PermissionDenied` 로 실패하는 경우와 구분된다 (전자는 개별 파일 권한, 후자는 폴더 자체 권한).

### 4.2 `cairn-preview` (신규, 최소 버전)

```rust
pub fn preview_text(
    path: &Path,
    max_bytes: usize,
) -> Result<String, PreviewError>;

pub enum PreviewError {
    Binary,                   // 첫 8KB에 NUL byte → binary 판정
    NotFound,
    PermissionDenied,
    Io(String),
}
```

**동작:**
- 첫 8KB 읽어 UTF-8 / NUL byte 검사
- binary 판정이면 `PreviewError::Binary` — Swift는 "미리보기 불가 (바이너리)" 메시지 표시
- 아니면 `max_bytes` 까지 읽어 Swift 로 반환. 초과 시 `"…(truncated)"` suffix.
- Syntax highlight 는 Phase 2 — 지금은 raw monospace 로만 렌더.

이미지 프리뷰는 Swift 쪽에서 `NSImage(contentsOf:)` + 256px 스케일링. `image` 크레이트 의존 회피.

### 4.3 `cairn-core` (Phase 0 skeleton 확장)

```rust
pub struct Engine {
    walker_config: WalkerConfig,
}

impl Engine {
    pub fn new() -> Self;
    pub fn list_directory(&self, path: &Path) -> Result<Vec<FileEntry>, WalkerError>;
    pub fn preview_text(&self, path: &Path) -> Result<String, PreviewError>;
    pub fn set_show_hidden(&mut self, show: bool);
}
```

Phase 0의 `pub fn hello()` 는 제거. `greet()` 도 제거.

### 4.4 `cairn-ffi` (Phase 0 대체)

```rust
#[swift_bridge::bridge]
mod ffi {
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

    enum FileKind { Directory, Regular, Symlink }

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

    enum PreviewError {
        Binary,
        NotFound,
        PermissionDenied,
        Io(String),
    }

    extern "Rust" {
        type Engine;

        fn new_engine() -> Engine;
        fn list_directory(&self, path: String) -> Result<Vec<FileEntry>, WalkerError>;
        fn preview_text(&self, path: String) -> Result<String, PreviewError>;
        fn set_show_hidden(&mut self, show: bool);
    }
}
```

## 5. Swift 앱 구조

### 5.1 디렉터리 레이아웃

```
apps/Cairn/Sources/
├── App/
│   ├── CairnApp.swift           @main, Settings Scene 자리, 최상위 키보드
│   └── AppModel.swift           @Observable: currentFolder, history, showHidden
├── Services/
│   ├── CairnEngine.swift        Rust FFI 래퍼 (async throws)
│   ├── BookmarkStore.swift      security-scoped bookmark CRUD
│   └── MountObserver.swift      NSWorkspace didMount / didUnmount → @Observable
├── Views/
│   ├── ContentView.swift        NavigationSplitView 세 패인 조합
│   ├── Sidebar/
│   │   ├── SidebarView.swift
│   │   ├── PinnedSection.swift
│   │   ├── RecentSection.swift
│   │   └── DevicesSection.swift
│   ├── FileList/
│   │   ├── FileListView.swift              NSViewRepresentable shell
│   │   ├── FileListNSTableView.swift       NSTableView 서브클래스
│   │   ├── FileListDataSource.swift        NSTableViewDataSource
│   │   └── FileListDelegate.swift          NSTableViewDelegate + 컨텍스트 메뉴
│   ├── Preview/
│   │   ├── PreviewPaneView.swift
│   │   └── PreviewRenderers.swift          TextPreview / ImagePreview / MetaOnly
│   ├── Breadcrumb/
│   │   └── BreadcrumbBar.swift
│   └── Onboarding/
│       └── OpenFolderEmptyState.swift
├── ViewModels/
│   ├── FolderModel.swift        entries, sortDescriptor, selection, loading
│   ├── SidebarModel.swift       pinned/recent/devices [BookmarkEntry]
│   └── PreviewModel.swift       현재 선택의 프리뷰 캐시 (LRU 16 entries)
├── Theme/
│   ├── CairnTheme.swift         struct 정의 + @Environment key
│   └── GlassBlue.swift          Theme.glass 인스턴스
├── Keyboard/
│   └── ShortcutMap.swift        전역 단축키 레지스트리
├── Generated/                   swift-bridge 아웃풋 (gitignored)
├── BridgingHeader.h
└── Cairn.entitlements           샌드박스 설정 (신규)
```

### 5.2 주요 클래스·구조체 계약

#### `AppModel`
```swift
@Observable
final class AppModel {
    var currentFolder: URL?           // 없으면 OpenFolderEmptyState
    var history: NavigationHistory    // 스택 + 현재 인덱스
    var showHidden: Bool = false      // ⌘⇧. 토글
    var theme: CairnTheme = .glass    // Phase 3까지 고정

    func navigate(to url: URL)        // history push + currentFolder set
    func goBack()                     // history index 감소
    func goForward()
    func goUp()                       // url.deletingLastPathComponent()
}

struct NavigationHistory {
    private var stack: [URL] = []
    private var index: Int = -1        // -1 == 비어있음, 0 이상은 stack 의 현재 위치

    var current: URL? { index >= 0 ? stack[index] : nil }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index < stack.count - 1 }

    mutating func push(_ url: URL) {
        // 앞으로 스택 위에 남은 항목은 버리고 새 URL 을 끝에 추가
        if index < stack.count - 1 { stack.removeSubrange((index + 1)..<stack.count) }
        stack.append(url)
        index = stack.count - 1
    }
    mutating func goBack() -> URL? { canGoBack ? { index -= 1; return stack[index] }() : nil }
    mutating func goForward() -> URL? { canGoForward ? { index += 1; return stack[index] }() : nil }
}
```

#### `CairnEngine`
```swift
@Observable
final class CairnEngine {
    private let rust: Engine

    init() { self.rust = new_engine() }

    func listDirectory(_ url: URL) async throws -> [FileEntry] {
        try await Task.detached { [rust] in
            try rust.list_directory(url.path)
        }.value
    }

    func previewText(_ url: URL) async throws -> String {
        try await Task.detached { [rust] in
            try rust.preview_text(url.path)
        }.value
    }

    func setShowHidden(_ show: Bool) { rust.set_show_hidden(show) }
}
```

#### `BookmarkStore`
```swift
struct BookmarkEntry: Codable, Identifiable {
    let id: UUID
    let bookmarkData: Data          // security-scoped bookmark blob
    var lastKnownPath: String       // 표시용
    let addedAt: Date
    var label: String?              // 선택적 — 유저가 이름 변경 가능 (Phase 2)
}

@Observable
final class BookmarkStore {
    var pinned: [BookmarkEntry]
    var recent: [BookmarkEntry]     // max 20, LRU

    func register(_ url: URL, kind: BookmarkKind) throws -> BookmarkEntry
    func resolve(_ entry: BookmarkEntry) -> URL?  // stale 면 nil, UI 가 ⚠️ 표시
    func startAccessing(_ entry: BookmarkEntry) -> Bool
    func stopAccessing(_ entry: BookmarkEntry)
    func pin(_ url: URL)            // ⌘D
    func unpin(_ entry: BookmarkEntry)
    func addRecent(_ url: URL)      // 폴더 진입 시 호출
}

enum BookmarkKind { case pinned, recent }
```

**Recent 중복 제거 규칙:** `url.standardized.resolvingSymlinksInPath().path` 기준으로 비교. 이미 있는 path 가 재방문되면 리스트에서 제거 후 최상단에 재삽입 (LRU). 최대 20개 초과 시 가장 오래된 항목 drop (bookmarkData 도 폐기).

영속성: `pinned` / `recent` 각각 JSON 으로 `~/Library/Containers/<bundle>/Data/Library/Application Support/Cairn/` 아래에 저장 (샌드박스 내 container path).

#### `MountObserver`
```swift
@Observable
final class MountObserver {
    var volumes: [URL]              // NSWorkspace.mountedLocalVolumeURLs

    init() {
        volumes = NSWorkspace.shared.mountedLocalVolumeURLs ?? []
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, ...
        )
        // 동일하게 didUnmount
    }
}
```

## 6. Theme B — Glass Blue tokens

```swift
struct CairnTheme: Equatable {
    let id: String
    let displayName: String

    // Window / panels
    let windowMaterial: NSVisualEffectView.Material  // .hudWindow
    let sidebarTint: Color
    let panelTint: Color

    // Text
    let text: Color
    let textSecondary: Color
    let textTertiary: Color

    // Accent
    let accent: Color
    let accentMuted: Color
    let selectionFg: Color

    // Geometry
    let cornerRadius: CGFloat
    let rowHeight: CGFloat
    let sidebarRowHeight: CGFloat
    let panelPadding: EdgeInsets

    // Typography
    let bodyFont: Font
    let monoFont: Font
    let headerFont: Font

    // Layout (Phase 1 엔 threePane 하나)
    let layout: LayoutVariant
}

enum LayoutVariant { case threePane, paletteFirst }

extension CairnTheme {
    static let glass = CairnTheme(
        id: "glass",
        displayName: "Glass (Blue)",
        windowMaterial: .hudWindow,
        sidebarTint: Color(hue: 0.62, saturation: 0.08, brightness: 0.14),
        panelTint:   Color(hue: 0.62, saturation: 0.06, brightness: 0.12),
        text:          Color(white: 0.93),
        textSecondary: Color(white: 0.60),
        textTertiary:  Color(white: 0.42),
        accent:        Color(red: 0.04, green: 0.52, blue: 1.00),   // #0A84FF
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

**NSVisualEffectView 적용 지점:**
- 루트 윈도우 배경 (`.hudWindow` — Ventura+ 네이티브 블러)
- 사이드바 + 프리뷰 패널: NSVisualEffectView 위에 tint 오버레이 (`panelTint` 값을 0.4 opacity 로)

테마 스위처·`UserDefaults` 영속성은 Phase 3. 지금은 `@Environment(\.cairnTheme)` 로 `.glass` 하나 고정 주입.

## 7. 샌드박스 & 온보딩

### 7.1 Entitlements (`apps/Cairn/Sources/Cairn.entitlements`)

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

`apps/project.yml` 에 `CODE_SIGN_ENTITLEMENTS: Sources/Cairn.entitlements` 추가.

### 7.2 온보딩 시퀀스

```
첫 실행 / bookmark 0개
  ↓
<OpenFolderEmptyState> (전체 화면 센터)
  🏔️
  "Open a folder to get started"
  [ Choose Folder… ]  (⌘O 도 바인딩)
  ↓ 클릭
NSOpenPanel.runModal(canChooseDirectories: true)
  ↓ 유저 선택
BookmarkStore.register(url, kind: .pinned)
  → security-scoped bookmark 생성
  → UserDefaults → Application Support JSON 저장
  ↓
AppModel.navigate(to: url)
  → FolderModel.load() → Rust list_directory
  ↓
three-pane UI 렌더
```

**첫 폴더는 자동 Pinned** — 단, 이는 **앱 라이프타임 최초 1회** 에만 적용 (저장된 pinned 가 0개일 때의 첫 NSOpenPanel 결과). 이후 새 윈도우(`⌘N`)에서의 폴더 열기는 자동 pin 안 됨 — 명시적 `⌘D` 필요.

### 7.3 Bookmark 라이프사이클

```
앱 시작
  ├─ BookmarkStore.loadAll() → 저장된 [BookmarkEntry]
  ├─ 각각 resolve() 시도
  │   ├─ 성공: SidebarModel 에 표시 (아직 scope 시작 안 함)
  │   └─ stale: ⚠️ 뱃지 유지 (유저가 우클릭 → "Locate…" 로 재프롬프트 — Phase 2)
  └─ scope 시작은 lazy — 실제 폴더 진입 시에만

폴더 진입 (Sidebar 클릭, breadcrumb 클릭, history back/forward 포함)
  ├─ bookmark resolve → url  (같은 bookmark 여도 매번 새로 resolve)
  ├─ url.startAccessingSecurityScopedResource() — 이전 폴더의 scope 는 stop 하지 않음
  ├─ Rust list_directory(url.path)
  ├─ FolderModel 갱신
  ├─ history push (새 진입이면) / history index 이동 (back/forward)
  └─ 같은 bookmark 에 대한 start/stop 은 참조 카운트 관리 (아래 규칙)

Scope 참조 카운트 규칙
  • 한 bookmark 에 대해 multiple start 는 안전하지만, **각 start 마다 대응되는 stop 필요**.
  • Phase 1 엔 단순화: "bookmark 당 active count" 를 BookmarkStore 가 들고 있다가,
    navigate 진입 시 +1 / 그 bookmark 를 사용하는 화면이 사라질 때 -1.
  • 구체적으론: currentFolder 가 bookmark A 에서 B 로 바뀔 때 → A -1, B +1.
    둘이 같으면 no-op. history back 때도 동일 룰 따라감.

앱 종료
  └─ SwiftUI Scene onDisappear 에서 모든 active count 만큼 stopAccessingSecurityScopedResource 호출.
     (macOS 가 프로세스 종료 시 정리해주지만, 명시적 cleanup 이 디버깅 편함.)
```

### 7.4 Devices 특례

- `NSWorkspace.mountedLocalVolumeURLs` 는 샌드박스 내 **열거 가능** (권한 불필요)
- 유저가 Devices 항목 클릭 → **NSOpenPanel 을 해당 볼륨 루트로 프리포지션** → 유저가 "Open" 누름 → security-scoped bookmark 생성 → 이후 자동 진입
- 언마운트 시 관련 bookmark 는 stale 로 마킹, 재마운트 시 재활성

## 8. 키보드 단축키 (Phase 1 범위)

| 키 | 동작 | 구현 위치 |
|---|---|---|
| `⌘O` | 폴더 열기 (NSOpenPanel) | `AppModel.openFolder()` |
| `⌘N` | 새 윈도우 | `CairnApp` Scene |
| `⌘↑` | 상위 폴더 | `AppModel.goUp()` |
| `⌘←` | 뒤로 | `AppModel.goBack()` |
| `⌘→` | 앞으로 | `AppModel.goForward()` |
| `⌘D` | 현재 폴더 pin 토글 | `BookmarkStore.pin/unpin` |
| `⌘R` | 현재 폴더 수동 새로고침 | `FolderModel.reload()` |
| `⌘⇧.` | 숨김 파일 토글 | `AppModel.showHidden` toggle |
| `Space` | Quick Look (선택 파일) | `NSResponder.quickLook(with:)` |
| `↑↓` | 파일 리스트 내비 | NSTableView 기본 |
| `↵` | 선택 열기 (디렉터리는 진입) | `FileListDelegate` |

Phase 2+ (⌘K 팔레트, ⌘⇧K Deep, ⌘1/2/3 패인 포커스) 는 문서에만 예약.

## 9. 수동 E2E 체크리스트 (Phase 1 완료 조건)

- [ ] 첫 실행 → NSOpenPanel → 유저가 `~/workspace` 선택 → 파일 리스트 렌더, 자동 Pinned 추가
- [ ] 파일 더블클릭 / `↵` → 폴더면 진입, 파일이면 `NSWorkspace.open`
- [ ] 브레드크럼 세그먼트 클릭 → 해당 경로로 네비게이션, 히스토리 push
- [ ] `⌘↑` 상위, `⌘←/→` 히스토리 (0 끝 비활성)
- [ ] 컬럼 헤더 클릭 → 정렬 방향 토글, 아이콘 표시
- [ ] 다중 선택 (`⇧↓`, `⌘클릭`) → 컨텍스트 메뉴 (Reveal in Finder / Copy Path / Move to Trash) 복수 대상 처리
- [ ] 파일 선택 → 프리뷰 패널에 텍스트 첫 2KB 또는 이미지 썸네일 또는 메타만
- [ ] `Space` → Quick Look 창, `Esc` / `Space` 로 닫기
- [ ] `⌘D` → 현재 폴더 Pinned 추가, 사이드바 즉시 반영, **앱 재시동 후에도 유지**
- [ ] 외장 USB 마운트 → Devices 섹션 즉시 추가, 언마운트 → 즉시 제거
- [ ] `⌘⇧.` → 숨김 파일 보임·사라짐, `.gitignore` 존중은 유지
- [ ] 권한 없는 폴더 진입 시도 → inline 에러 메시지 + 재프롬프트 링크
- [ ] `cargo test --workspace` 녹색, `cargo clippy -- -D warnings` 녹색
- [ ] CI (rust + swift job) 녹색
- [ ] v0.1.0-alpha 태그 + DMG 빌드 실험 (distribution 엔 미등록 OK)

## 10. 테스트 전략

| 레이어 | 유형 | 도구 |
|---|---|---|
| Rust 크레이트 | 단위 테스트 (tempdir fixtures) | `cargo test`, `tempfile` |
| `cairn-walker` | integration — 실제 fixture tree 순회 | `tempfile` + 수동 assertion |
| Swift Services (BookmarkStore, MountObserver) | XCTest 단위 | Xcode 내장 |
| Swift Views | 시각 회귀는 **Phase 2 이후** | (Phase 1 엔 안 함) |
| E2E | 수동 체크리스트 (§ 9) | 개발자 손 |

CI 는 Phase 0 yaml 을 유지하되 `cargo test --workspace` 가 `cairn-walker` / `cairn-preview` 신규 테스트를 포함하도록 자동 확장. Swift 유닛 테스트 타깃은 `CairnTests` 로 추가 (xcodegen `targets.CairnTests`).

## 11. 2.75개월 마일스톤 (6 × 2주)

| M | 이름 | 결과물 |
|---|---|---|
| **1.1** | Rust walker + 최소 SwiftUI 리스트 + 샌드박스 스캐폴드 | `cairn-walker` + 확장 `cairn-core` + `cairn-ffi` 교체. Entitlements 파일, OpenFolderEmptyState, SwiftUI `List` 로 1-컬럼 파일 목록, bookmark 최소 CRUD (저장·해결). |
| **1.2** | NSTableView 정식 리스트 + 정렬 + 다중 선택 | FileListView(NSViewRep) + DataSource + Delegate, 3 컬럼 (Name/Size/Modified), 헤더 클릭 정렬, ↑↓ 키보드 네비, `⇧↓` / `⌘클릭` 다중 선택. |
| **1.3** | 사이드바 (Pinned/Recent/Devices) + Breadcrumb | SidebarView + 3 Section, MountObserver 구현, BookmarkStore recent 로직, BreadcrumbBar, `⌘D` / `⌘↑` / `⌘←→`. |
| **1.4** | `cairn-preview` + PreviewPaneView + Quick Look | Rust `preview_text`, 이미지 썸네일 Swift, MetaOnly 분기, Space → `QLPreviewPanel`, `⌘⇧.` 숨김 토글. |
| **1.5** | Theme B · Glass Blue + 컨텍스트 메뉴 | `CairnTheme` struct, `Theme.glass`, NSVisualEffectView 통합, 컨텍스트 메뉴 (Reveal / Copy Path / Trash) via `NSWorkspace` / `FileManager.trashItem`. |
| **1.6** | 폴리싱 + 버그 + v0.1.0-alpha | E2E 체크리스트 완주, README 업데이트, `create-dmg` 실험, `git tag v0.1.0-alpha`. |

매 마일스톤 끝에 `git tag phase-1-m1.X` 로 기준점. CI 녹색 아니면 다음 진입 금지.

## 12. 리스크 & 완화

| 리스크 | 완화 |
|---|---|
| NSTableView 러닝커브 (SwiftUI 처음 유저) | M1.2 전에 별도 1일 스파이크 — Apple 공식 샘플 따라해보고 시작 |
| Sandbox bookmark 미묘한 lifetime 버그 | BookmarkStore에 단위 테스트 필수. 앱 종료 전 `stopAccessingSecurityScopedResource` 빠뜨리면 다음 launch 에 resolve 실패 가능 |
| swift-bridge `Result<T, E>` 매핑이 0.1.x에서 기대대로 안 될 경우 | 폴백: Rust 에서 `enum CallResult { Ok(T), Err(WalkerError) }` 수동 enum 리턴 |
| Theme B 의 NSVisualEffectView 블러가 macOS 13 에서 Sonoma 와 비주얼 차이 클 경우 | 최소 13 유지하되 `.hudWindow` 가 아닌 `.sidebar` material 로 폴백 옵션 |
| 마일스톤 1.2 / 1.3 이 예상보다 어려워 2.5 → 3.5개월로 연장 | 각 M 끝 평가에서 솔직하게 밀리는 판단. Phase 2 일정 연동 재조정 |

## 13. 로드맵 연결

Phase 1 종료 후 Phase 2 인풋:
- `cairn-walker` 는 Phase 2 Deep search 에 재사용 (`jwalk` 병렬성 활용)
- `cairn-preview` 는 Phase 2 에서 syntax highlight (tree-sitter) 추가
- `FolderModel` / `FileEntry` 스키마는 검색 결과 뷰에도 그대로 사용
- FSEvents 구독은 Phase 2 시작 때 `cairn-index` 와 함께 도입

## 14. 부록: 데이터 플로우 예시

**"Sidebar 의 Pinned 항목을 클릭해서 폴더 진입" 이 코드 흐름:**

```
사이드바 클릭 (PinnedSection)
  → SidebarModel.didSelect(entry)
  → AppModel.navigate(to: url)
    → BookmarkStore.startAccessing(entry)  (URL 확정, scoped access 시작)
    → history.push(url)
    → currentFolder = url
  → ContentView 에서 FolderModel.load(url) 호출 (@Observable 트리거)
    → engine.listDirectory(url)  (Swift async)
      → Task.detached { rust.list_directory(url.path) }
        → Rust cairn_core::Engine.list_directory
          → cairn_walker::list_directory(path, config)
            → ignore::Walk + metadata
            → FileEntry Vec 빌드
        → swift-bridge Result → Swift throws
    → FolderModel.entries = [FileEntry]
    → 로딩 플래그 해제
  → FileListView (NSViewRep) 바인딩 → NSTableView reload
  → BookmarkStore.addRecent(url)  (사이드바 Recent 섹션 갱신)
```

---

*이 문서는 superpowers:writing-plans 의 입력으로 사용된다. 구현 플랜은 각 마일스톤(M1.1–M1.6)을 별도 `docs/superpowers/plans/YYYY-MM-DD-cairn-phase-1-M<X>.md` 로 쪼개거나, 단일 `cairn-phase-1-foundation.md` 로 묶을지 작성 시 결정.*
