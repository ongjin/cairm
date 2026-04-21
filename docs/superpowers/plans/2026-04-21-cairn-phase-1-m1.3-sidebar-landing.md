# Cairn Phase 1 · M1.3 — Finder-like Sidebar + 디폴트 랜딩 + BreadcrumbBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** M1.2 의 NSTableView 파일 리스트 위에 **Finder 수준의 사이드바 + 디폴트 랜딩 + BreadcrumbBar** 를 올린다. 더 이상 `OpenFolderEmptyState` 로 gate 를 치지 않고, 앱 실행 즉시 3-pane 파인더-like 레이아웃이 보인다. 사이드바는 **Pinned / Recent / iCloud Drive / Locations** 4 섹션. `⌘D` 로 현재 폴더 핀 토글, 우클릭 메뉴에 "Add to Pinned" 추가. 마운트된 볼륨은 `MountObserver` 로 실시간 반영.

**Scope 확장 배경 (2026-04-21 유저 결정):** 원래 spec 의 M1.3 범위 (Pinned/Recent/Devices 3 섹션) 에 iCloud Drive 를 v2.0 → Phase 1 으로 당기고, `OpenFolderEmptyState` gate 제거 + 디폴트 랜딩 (최초 Home, 이후 lastFolder) 을 추가. 상세 근거는 `/Users/cyj/.claude/projects/-Users-cyj-workspace-personal-cairn/memory/project_finder_replacement_pivot.md` 참조.

**Architecture:**
- **디폴트 랜딩:** `AppModel` 이 init 시점에 `LastFolderStore.load()` 로 직전 실행 때 저장한 URL 을 복원. 없거나 존재하지 않는 경로면 `FileManager.default.homeDirectoryForCurrentUser` 로 폴백. 복원된 URL 은 바로 `history.push` 되고 `BookmarkStore` 에는 등록 안 함 (개발 빌드에선 sandbox 가 안 먹으므로 그냥 열리고, M1.6 signing 후엔 `com.apple.security.files.user-selected` 권한 범위 안에 있으면 성공, 밖이면 `FolderModel.state = .failed` 로 떨어져 사용자가 NSOpenPanel 로 재진입).
- **SidebarModel (@Observable):** `locations: [URL]` 만 합성 (Computer 루트 + mounts). Pinned / Recent 는 뷰가 직접 `BookmarkStore` 를 읽고, iCloud Drive 는 URL 하나를 `SidebarModel.iCloudURL` 에 노출 (경로가 실제 존재할 때만). MountObserver 를 주입받아 `volumes` 변화를 수신.
- **MountObserver:** `NSWorkspace.shared.notificationCenter` 의 `didMountNotification` / `didUnmountNotification` 을 구독. 초기값은 `NSWorkspace.shared.mountedLocalVolumeURLs`.
- **SidebarView:** SwiftUI `List` 4 섹션. 클릭 시 `AppModel` 으로 navigate. 우클릭 메뉴 (Pinned 항목 → "Unpin", 다른 항목 → "Add to Pinned" / "Reveal in Finder").
- **BreadcrumbBar:** toolbar 에 올리는 horizontal 경로 세그먼트. `currentFolder.pathComponents` 를 훑어 각 세그먼트를 버튼으로 렌더; 클릭 → 해당 상위 경로로 `history.push`.
- **`⌘D` pin 토글:** `AppModel.toggleCurrentFolderPin()` — 현재 폴더 URL 이 `bookmarks.pinned` 에 있으면 unpin, 없으면 register(.pinned).
- **우클릭 "Add to Pinned":** `FileListCoordinator` 에 `tableView(_:menuFor:)` delegate 추가. NSMenu 로 하나만: "Add to Pinned" → `bookmarks.register(entry.path, kind: .pinned)`. 현재 이미 pinned 면 비활성. 파일 (non-directory) 인 행은 메뉴 표시 안 함 (Phase 1 은 폴더만 핀).

**Tech Stack:** Swift 5.9 · SwiftUI (`NavigationSplitView`, `List`) · AppKit (`NSWorkspace`, `NSMenu`) · `@Observable` · macOS 14+ · UserDefaults (lastFolder path persistence) · 기존 `cairn-walker`/`cairn-ffi` 변경 없음

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main branch, 시작 시점 HEAD 는 `phase-1-m1.2` 태그, SHA `1c61ab0`)

**Predecessor:** M1.2 — `docs/superpowers/plans/2026-04-21-cairn-phase-1-m1.2-nstableview.md` (완료)
**Parent spec:** `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md` § 11 M1.3 + 2026-04-21 scope expansion (iCloud 포함, empty-state 제거)

**Deliverable verification (M1.3 완료 조건):**
- `cargo test --workspace` 녹색 (regression)
- `xcodebuild -scheme Cairn build` 성공
- `xcodebuild test -scheme CairnTests` 녹색 — 신규 `SidebarModelTests` + `MountObserverTests` + `LastFolderStoreTests` 합 ≥ 7 케이스 + 기존 10 = 17 통과
- 앱 실행 → **empty state 안 뜸.** 3-pane (Sidebar · FileList · Preview placeholder) 바로 렌더. 최초 실행은 Home, 이후엔 마지막 폴더.
- 사이드바에 Pinned (최초 비었음) / Recent (최초 비었음) / iCloud Drive (있으면 뜸) / Locations (Computer + 외장 볼륨 있으면 거기도 뜸) 네 섹션 모두 표시.
- 현재 폴더 위에서 `⌘D` → Pinned 섹션에 즉시 추가, 한 번 더 누르면 제거.
- 파일 리스트 행 우클릭 (디렉터리) → "Add to Pinned" 동작.
- 외장 USB 마운트 / 언마운트 → Locations 즉시 반영.
- BreadcrumbBar 세그먼트 클릭 → 해당 경로로 이동.
- `git tag phase-1-m1.3` 로 기준점.

---

## 1. 기술 참조 (M1.3 특유 함정)

- **`NSWorkspace.shared.notificationCenter` vs `NotificationCenter.default`** — 마운트 알림은 **전자만** fire. 일반 `NotificationCenter.default.addObserver` 로는 안 잡힘.
- **`mountedLocalVolumeURLs` 리턴 시점** — 앱 init 시점에 호출해도 현재 마운트 상태 리턴. 초기 스캔 + 이후 notification 둘 다 필요.
- **iCloud Drive 경로** — `~/Library/Mobile Documents/com~apple~CloudDocs`. `FileManager.default.url(forUbiquityContainerIdentifier: nil)` 는 iCloud 엔티틀먼트 없으면 nil 리턴하므로 대신 고정 경로로 `FileManager.default.fileExists(atPath:)` 체크.
- **`FileManager.default.homeDirectoryForCurrentUser`** — 개발 빌드 (unsigned, non-sandbox) 에서는 사용자 실제 Home 을 리턴. sandbox 빌드에선 `~/Library/Containers/<bundle-id>/Data` 를 리턴 — M1.6 에서 signing 후 재검증.
- **SwiftUI `NavigationSplitView` + `List` selection** — `List(selection: $selection)` 로 단일 선택 상태 관리. 사이드바는 단일 선택만 의미 있음 (동시에 두 폴더 열지 않음).
- **NSMenu delegate 에서 `clickedRow` 해석** — `tableView.clickedRow` 는 우클릭이 **터진 행** 의 인덱스 (선택된 행이 아님). 우클릭이 빈 공간이면 `-1`.
- **UserDefaults 경로 저장 시 URL vs String** — `URL` 자체는 `Codable` 이지만 그대로 넣으면 다소 verbose. `url.path` (String) 으로 저장하고 복원 시 `URL(fileURLWithPath:)` 이 더 깔끔.
- **`@Observable` + `NotificationCenter` observer 해제** — `@Observable` 로 관찰 아이템을 만들면 deinit 타이밍이 명시적이지 않음. NSObject 서브클래스로 만들고 `deinit` 에서 `notificationCenter.removeObserver(self)` 호출해야 leak 안 남.

---

## 2. File Structure

**Swift (apps/Sources/):**
- Create: `apps/Sources/Services/MountObserver.swift` — `@Observable` wrapper around NSWorkspace mount notifications.
- Create: `apps/Sources/Services/LastFolderStore.swift` — UserDefaults-backed `save(_:)` / `load()` for last-opened folder path.
- Create: `apps/Sources/ViewModels/SidebarModel.swift` — composition of locations (Computer + mounts) + iCloud URL; injects MountObserver.
- Create: `apps/Sources/Views/Sidebar/SidebarView.swift` — SwiftUI List with 4 sections + right-click menu.
- Create: `apps/Sources/Views/Sidebar/SidebarItemRow.swift` — shared row renderer (icon + label + optional trailing badge).
- Create: `apps/Sources/Views/BreadcrumbBar.swift` — horizontal path-segment toolbar item.
- Modify: `apps/Sources/App/AppModel.swift` — default landing resolution, `toggleCurrentFolderPin()`, lastFolder save on `currentFolder` changes, inject SidebarModel + MountObserver.
- Modify: `apps/Sources/ContentView.swift` — remove empty-state branch, wire SidebarView + BreadcrumbBar, add `⌘D`, keep `⌘O` behavior for explicit folder open.
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift` — add `tableView(_:menuForEvent:)` returning NSMenu with "Add to Pinned". (Extends existing file; doesn't touch existing DataSource/Delegate logic.)
- Modify: `apps/Sources/Services/BookmarkStore.swift` — add `isPinned(path:)` and `togglePin(url:)` convenience helpers (pure delegation to existing register/unpin; no new state).
- Delete: `apps/Sources/Views/Onboarding/OpenFolderEmptyState.swift` — gate removed.
- Delete (if empty): `apps/Sources/Views/Onboarding/` directory after the above.

**Swift tests (apps/CairnTests/):**
- Create: `apps/CairnTests/MountObserverTests.swift` — 1 test: initial `volumes` reflects `NSWorkspace.mountedLocalVolumeURLs`.
- Create: `apps/CairnTests/LastFolderStoreTests.swift` — 3 tests: save/load round-trip; load returns nil for missing key; load returns nil for nonexistent path.
- Create: `apps/CairnTests/SidebarModelTests.swift` — 3 tests: iCloud URL presence behavior (existing + nonexistent); `locations` updates when MountObserver's `volumes` changes.

**Rust:** 변경 없음.

**참고:** `BookmarkStore` 는 `M1.1` 에서 완성된 상태 유지. `FolderModel` 도 M1.2 에서 확정된 상태 유지 (변경 없음).

---

## Task 1: `MountObserver` — 마운트 볼륨 구독 (TDD)

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Services/MountObserver.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/CairnTests/MountObserverTests.swift`

`NSWorkspace.shared.notificationCenter` 의 `didMountNotification` / `didUnmountNotification` 을 구독해 `volumes: [URL]` 을 최신 상태로 유지. 초기값은 `NSWorkspace.shared.mountedLocalVolumeURLs`.

- [ ] **Step 1: `MountObserverTests.swift` — 실패 테스트 작성**

```swift
import XCTest
@testable import Cairn

final class MountObserverTests: XCTestCase {
    /// Basic sanity: freshly-constructed observer reflects the current mount state.
    /// Cannot simulate real mount/unmount in unit test; M1.3 E2E handles that.
    func test_initial_volumes_match_nsworkspace_snapshot() {
        let observer = MountObserver()
        let expected = Set(NSWorkspace.shared.mountedLocalVolumeURLs ?? [])
        XCTAssertEqual(Set(observer.volumes), expected)
    }
}
```

- [ ] **Step 2: 테스트 실행 — 컴파일 에러 확인 (★ 실패 예상 ★)**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -20
```

Expected: `Cannot find 'MountObserver' in scope`. TDD red.

- [ ] **Step 3: `MountObserver.swift` 작성**

```swift
import AppKit
import Observation

/// Observes macOS volume mount / unmount events and maintains an up-to-date list
/// of local mounted volume URLs. Used by SidebarModel to populate the Locations
/// section.
///
/// Subclassing NSObject lets us use `#selector` with NotificationCenter, and gives
/// us a deterministic `deinit` for observer teardown.
@Observable
final class MountObserver: NSObject {
    /// Current mounted local volumes (e.g. `/`, `/Volumes/ExternalDisk`).
    /// Populated synchronously from NSWorkspace at init; updated on mount/unmount
    /// notifications.
    private(set) var volumes: [URL]

    private let workspace: NSWorkspace

    override init() {
        self.workspace = NSWorkspace.shared
        self.volumes = workspace.mountedLocalVolumeURLs ?? []
        super.init()

        let nc = workspace.notificationCenter
        nc.addObserver(self,
                       selector: #selector(reload(_:)),
                       name: NSWorkspace.didMountNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(reload(_:)),
                       name: NSWorkspace.didUnmountNotification,
                       object: nil)
    }

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }

    @objc private func reload(_ note: Notification) {
        // Re-query on any mount change. List is always small (< 20 on a normal
        // workstation) so the full re-read is fine.
        volumes = workspace.mountedLocalVolumeURLs ?? []
    }
}
```

- [ ] **Step 4: 테스트 재실행 — 통과 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 11/11 (기존 10 + MountObserver 1). 실패 시 STOP.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Services/MountObserver.swift apps/CairnTests/MountObserverTests.swift
git commit -m "feat(mount-observer): add NSWorkspace mount/unmount observer"
```

---

## Task 2: `LastFolderStore` — 마지막 폴더 경로 영속화 (TDD)

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Services/LastFolderStore.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/CairnTests/LastFolderStoreTests.swift`

UserDefaults 에 `cairn.lastFolderPath` 키로 저장. `load()` 는 존재 파일만 리턴.

- [ ] **Step 1: `LastFolderStoreTests.swift` — 실패 테스트 작성**

```swift
import XCTest
@testable import Cairn

final class LastFolderStoreTests: XCTestCase {
    /// Uses a fresh UserDefaults suite per test so runs don't leak into the real
    /// defaults or into each other.
    private func freshDefaults() -> UserDefaults {
        let suite = "LastFolderStoreTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_save_then_load_roundtrip() throws {
        let d = freshDefaults()
        let store = LastFolderStore(defaults: d)
        let tmp = FileManager.default.temporaryDirectory
        store.save(tmp)
        XCTAssertEqual(store.load()?.standardizedFileURL, tmp.standardizedFileURL)
    }

    func test_load_returns_nil_when_key_absent() {
        let d = freshDefaults()
        let store = LastFolderStore(defaults: d)
        XCTAssertNil(store.load())
    }

    func test_load_returns_nil_when_path_no_longer_exists() {
        let d = freshDefaults()
        let store = LastFolderStore(defaults: d)
        let ghost = URL(fileURLWithPath: "/tmp/definitely-not-there-\(UUID().uuidString)")
        store.save(ghost)
        XCTAssertNil(store.load())
    }
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -10
```

Expected: `Cannot find 'LastFolderStore' in scope`.

- [ ] **Step 3: `LastFolderStore.swift` 작성**

```swift
import Foundation

/// Remembers the last folder the user was viewing so we can restore it on next
/// launch. Stored as a POSIX path string in UserDefaults — simple and doesn't
/// require an active bookmark (the bookmark layer is a separate concern).
///
/// `load()` defensively returns nil if the stored path no longer exists on disk,
/// letting AppModel fall back to Home without surfacing a stale error.
struct LastFolderStore {
    private let defaults: UserDefaults
    private let key = "cairn.lastFolderPath"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ url: URL) {
        defaults.set(url.standardizedFileURL.path, forKey: key)
    }

    func load() -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
```

- [ ] **Step 4: 테스트 재실행 — 3/3 통과**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 14/14 (기존 11 + LastFolder 3).

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Services/LastFolderStore.swift apps/CairnTests/LastFolderStoreTests.swift
git commit -m "feat(last-folder-store): add UserDefaults-backed lastFolder path persistence"
```

---

## Task 3: `SidebarModel` — Locations + iCloud 합성 (TDD)

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/ViewModels/SidebarModel.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/CairnTests/SidebarModelTests.swift`

사이드바 4 섹션 중 2 개 (iCloud · Locations) 를 합성. Pinned / Recent 는 View 가 `BookmarkStore` 직접 구독하므로 SidebarModel 에 안 둠 (DRY).

- [ ] **Step 1: `SidebarModelTests.swift` — 실패 테스트 작성**

```swift
import XCTest
@testable import Cairn

final class SidebarModelTests: XCTestCase {
    /// MountObserver is injected so tests can stub the volumes list via a test-only
    /// helper on MountObserver (see setTestVolumes).
    private var observer: MountObserver!

    override func setUpWithError() throws {
        observer = MountObserver()
    }

    func test_locations_starts_with_computer_root_first() {
        let model = SidebarModel(mountObserver: observer)
        XCTAssertEqual(model.locations.first, URL(fileURLWithPath: "/"))
    }

    func test_locations_includes_mounted_volumes() {
        let model = SidebarModel(mountObserver: observer)
        // Every entry in observer.volumes should appear in model.locations.
        for vol in observer.volumes {
            XCTAssertTrue(model.locations.contains(vol),
                          "Expected \(vol) in locations but got \(model.locations)")
        }
    }

    func test_icloud_url_present_iff_path_exists() {
        let model = SidebarModel(mountObserver: observer)
        let expected = FileManager.default.fileExists(
            atPath: SidebarModel.iCloudDrivePath.path)
        XCTAssertEqual(model.iCloudURL != nil, expected)
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -10
```

Expected: `Cannot find 'SidebarModel' in scope`.

- [ ] **Step 3: `SidebarModel.swift` 작성**

```swift
import Foundation
import Observation

/// Composes the two "synthetic" sidebar sections whose content is not
/// bookmark-backed: iCloud Drive (a single well-known path) and Locations
/// (computer root + live mounted volumes).
///
/// Pinned and Recent are read directly from BookmarkStore by SidebarView — no
/// reason to mirror them here.
@Observable
final class SidebarModel {
    /// Well-known path to iCloud Drive's local mirror. Works without the iCloud
    /// entitlement because we only check disk existence; navigating in is a
    /// regular file URL access. Users without iCloud signed in won't have this
    /// directory, and we silently hide the section.
    static let iCloudDrivePath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")

    /// Nil when iCloud Drive isn't set up on this machine.
    private(set) var iCloudURL: URL?

    /// Computer root (`/`) followed by currently-mounted local volumes in the
    /// order NSWorkspace reports them.
    private(set) var locations: [URL]

    private let mountObserver: MountObserver
    /// Observation token retained to receive mount changes. We track through
    /// @Observable's implicit observation rather than an explicit subscriber,
    /// keyed on the observer's `volumes` property.
    private var observationTask: Task<Void, Never>?

    init(mountObserver: MountObserver) {
        self.mountObserver = mountObserver
        self.iCloudURL = FileManager.default.fileExists(atPath: Self.iCloudDrivePath.path)
            ? Self.iCloudDrivePath
            : nil
        self.locations = Self.composeLocations(from: mountObserver.volumes)

        // Recompute `locations` whenever observer.volumes changes.
        // @Observable's withObservationTracking requires manual re-arming
        // after each fire — a simple long-running task loops for us.
        self.observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await withCheckedContinuation { cont in
                    withObservationTracking {
                        _ = self?.mountObserver.volumes
                    } onChange: {
                        cont.resume()
                    }
                }
                guard let self else { return }
                self.locations = Self.composeLocations(from: self.mountObserver.volumes)
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private static func composeLocations(from volumes: [URL]) -> [URL] {
        var out: [URL] = [URL(fileURLWithPath: "/")]
        for v in volumes where v.path != "/" {
            out.append(v)
        }
        return out
    }
}
```

- [ ] **Step 4: 테스트 재실행**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 17/17 (기존 14 + Sidebar 3).

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ViewModels/SidebarModel.swift apps/CairnTests/SidebarModelTests.swift
git commit -m "feat(sidebar-model): add SidebarModel composing iCloud + Locations sections"
```

---

## Task 4: `BookmarkStore` 확장 — `isPinned` / `togglePin`

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Services/BookmarkStore.swift`

핀 토글 (⌘D, 우클릭 메뉴) 에서 쓰는 편의 함수. 기존 로직 건드리지 않고 **뒤에 메서드 두 개 추가**.

- [ ] **Step 1: `BookmarkStore` 에 메서드 추가**

`BookmarkStore.swift` 의 `unpin(_:)` 메서드 바로 아래에 (다음 `// MARK: - Resolution` 주석 위에) 다음을 삽입:

```swift
    /// Returns true iff a pinned entry currently points to `url` (path-based
    /// comparison, standardized).
    func isPinned(url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return pinned.contains { $0.lastKnownPath == p }
    }

    /// Pin `url` if it's not already pinned; unpin if it is. Idempotent toggle
    /// used by `⌘D` and sidebar "Unpin" menu item. Throws if bookmark creation
    /// fails on register.
    func togglePin(url: URL) throws {
        let p = url.standardizedFileURL.path
        if let existing = pinned.first(where: { $0.lastKnownPath == p }) {
            unpin(existing)
        } else {
            _ = try register(url, kind: .pinned)
        }
    }
```

- [ ] **Step 2: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 기존 테스트 regression 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 17/17 여전히 통과 (기존 BookmarkStoreTests 포함).

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Services/BookmarkStore.swift
git commit -m "feat(bookmarks): add isPinned(url:) and togglePin(url:) helpers"
```

---

## Task 5: `AppModel` — 디폴트 랜딩 + lastFolder 저장 + pin 토글

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/App/AppModel.swift`

변경점:
1. `lastFolder: LastFolderStore` 프로퍼티 주입.
2. `sidebar: SidebarModel` + `mountObserver: MountObserver` 프로퍼티 주입 (뷰가 `@Environment` 로 쉽게 접근).
3. init 종료 시 `bootstrapInitialFolder()` 호출 — lastFolder 복원, 없으면 Home 으로.
4. `currentFolder` 가 바뀔 때마다 `lastFolder.save(url)` — `didSet` 없이 `history.push` 쪽을 통해. AppModel 은 현재 `history.push` 를 직접 노출하지 않으므로, 대신 navigate/goUp/goBack/goForward 가 실행된 후 명시적으로 저장하는 helper 를 두면 됨. 간단히: `pushAndRemember(_:)` 을 내부에 두거나, ContentView 쪽에서 `onChange(of: app.currentFolder)` 감지해 `app.lastFolder.save(url)`. 후자가 덜 침습적이므로 **ContentView 의 `onChange` 에서 호출하는 방식** 을 선택 (Task 7 에서).
5. `toggleCurrentFolderPin()` 메서드 추가.

- [ ] **Step 1: `AppModel.swift` 교체**

```swift
import Foundation
import Observation
import SwiftUI

/// Top-level application state. Single instance injected via @Environment.
///
/// M1.3 additions:
///   - `sidebar` / `mountObserver` so Views can observe via the same AppModel.
///   - `lastFolder` to persist the current folder across launches.
///   - `bootstrapInitialFolder()` — runs at end of init to restore lastFolder
///     or fall back to Home. No more OpenFolderEmptyState gate.
@Observable
final class AppModel {
    var history = NavigationHistory()
    var showHidden: Bool = false

    /// The bookmark entry currently "in use" (security-scoped access started).
    /// nil when we're in Home or a volume root that doesn't need bookmarking
    /// (dev builds bypass sandbox; under sandbox this will need a bookmark in M1.6).
    var currentEntry: BookmarkEntry?

    let engine: CairnEngine
    let bookmarks: BookmarkStore
    let lastFolder: LastFolderStore
    let mountObserver: MountObserver
    let sidebar: SidebarModel

    init(engine: CairnEngine = CairnEngine(),
         bookmarks: BookmarkStore = BookmarkStore(),
         lastFolder: LastFolderStore = LastFolderStore()) {
        self.engine = engine
        self.bookmarks = bookmarks
        self.lastFolder = lastFolder
        let observer = MountObserver()
        self.mountObserver = observer
        self.sidebar = SidebarModel(mountObserver: observer)
        bootstrapInitialFolder()
    }

    /// The URL currently displayed (equal to history.current when present).
    var currentFolder: URL? { history.current }

    // MARK: - Bootstrap

    /// Restores the last-viewed folder, falling back to the user's home
    /// directory. Called once at the end of init — after this returns,
    /// `currentFolder` is guaranteed non-nil for the lifetime of the app
    /// (absent user action that clears history, which Phase 1 doesn't expose).
    private func bootstrapInitialFolder() {
        let url = lastFolder.load() ?? FileManager.default.homeDirectoryForCurrentUser
        history.push(url)
    }

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

        // Add to recent unless the user is explicitly re-selecting from the
        // Recent section — cheap heuristic: only auto-add when entering from pin.
        if entry.kind == .pinned {
            try? bookmarks.register(url, kind: .recent)
        }
    }

    /// Navigate to an arbitrary URL that we don't (yet) have a bookmark for.
    /// Used by sidebar Locations items (Computer root, mounted volumes) and by
    /// the default-landing bootstrap. Under sandbox this will fail at
    /// listDirectory time and surface a `.failed` state — M1.6 polishes that.
    func navigateUnscoped(to url: URL) {
        if let prev = currentEntry {
            bookmarks.stopAccessing(prev)
            currentEntry = nil
        }
        history.push(url)
    }

    /// Register a freshly-chosen folder (from NSOpenPanel) as pinned if it's the
    /// user's very first folder, otherwise as recent. Then navigate to it.
    func openAndNavigate(to url: URL, autoPinIfFirst: Bool = true) throws {
        let isFirst = bookmarks.pinned.isEmpty && autoPinIfFirst
        let entry = try bookmarks.register(url, kind: isFirst ? .pinned : .recent)
        navigate(to: entry)
    }

    /// Move up one level. No-op at `/`.
    func goUp() {
        guard let url = currentFolder else { return }
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { return }
        history.push(parent)
    }

    func goBack() { _ = history.goBack() }
    func goForward() { _ = history.goForward() }

    func toggleShowHidden() {
        showHidden.toggle()
        engine.setShowHidden(showHidden)
    }

    // MARK: - Pinning

    /// `⌘D` and right-click "Add to Pinned" / "Unpin" enter here.
    /// No-op if there's no current folder (shouldn't happen after bootstrap).
    func toggleCurrentFolderPin() {
        guard let url = currentFolder else { return }
        try? bookmarks.togglePin(url: url)
    }
}
```

- [ ] **Step 2: 빌드 — `** BUILD SUCCEEDED **`**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

- [ ] **Step 3: 기존 전체 테스트 통과 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 17/17 여전히 통과.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/App/AppModel.swift
git commit -m "feat(app-model): default landing + navigateUnscoped + toggleCurrentFolderPin"
```

---

## Task 6: `SidebarItemRow` + `SidebarView`

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Sidebar/SidebarItemRow.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Sidebar/SidebarView.swift`

4-section `List`. 각 행은 icon + label. 우클릭 메뉴는 Pinned 항목은 "Unpin" / "Reveal in Finder", 나머지는 "Add to Pinned" / "Reveal in Finder" (폴더인 경우).

- [ ] **Step 1: `SidebarItemRow.swift` 작성**

```swift
import SwiftUI

/// Single sidebar row — icon + label. Used for every section so all items line
/// up visually and we have one place to tune padding/size.
struct SidebarItemRow: View {
    let icon: String      // SF Symbol name
    let label: String
    let tint: Color?      // if nil, label color is used

    var body: some View {
        Label {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint ?? .primary)
                .frame(width: 16)
        }
        .font(.system(size: 12))
        .padding(.vertical, 1)
    }
}
```

- [ ] **Step 2: `SidebarView.swift` 작성**

```swift
import SwiftUI
import AppKit

/// Finder-like 4-section sidebar: Pinned / Recent / iCloud Drive / Locations.
/// Clicking an item navigates via AppModel. Right-click gives "Add to Pinned",
/// "Unpin", or "Reveal in Finder" depending on the item's section.
struct SidebarView: View {
    @Bindable var app: AppModel

    var body: some View {
        List {
            if !app.bookmarks.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(app.bookmarks.pinned) { entry in
                        pinnedRow(entry)
                    }
                }
            }

            if !app.bookmarks.recent.isEmpty {
                Section("Recent") {
                    ForEach(app.bookmarks.recent) { entry in
                        recentRow(entry)
                    }
                }
            }

            if let iCloud = app.sidebar.iCloudURL {
                Section("iCloud") {
                    row(url: iCloud,
                        icon: "icloud",
                        label: "iCloud Drive",
                        tint: .blue,
                        canPin: true)
                }
            }

            Section("Locations") {
                ForEach(app.sidebar.locations, id: \.self) { loc in
                    row(url: loc,
                        icon: loc.path == "/" ? "desktopcomputer" : "externaldrive",
                        label: locationLabel(loc),
                        tint: nil,
                        canPin: true)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    // MARK: - Rows

    private func pinnedRow(_ entry: BookmarkEntry) -> some View {
        SidebarItemRow(
            icon: "pin.fill",
            label: entry.label ?? URL(fileURLWithPath: entry.lastKnownPath).lastPathComponent,
            tint: .orange
        )
        .contentShape(Rectangle())
        .onTapGesture { app.navigate(to: entry) }
        .contextMenu {
            Button("Unpin") { app.bookmarks.unpin(entry) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(entry.lastKnownPath,
                                              inFileViewerRootedAtPath: "")
            }
        }
    }

    private func recentRow(_ entry: BookmarkEntry) -> some View {
        SidebarItemRow(
            icon: "clock",
            label: URL(fileURLWithPath: entry.lastKnownPath).lastPathComponent,
            tint: nil
        )
        .contentShape(Rectangle())
        .onTapGesture { app.navigate(to: entry) }
        .contextMenu {
            Button("Add to Pinned") { try? app.bookmarks.togglePin(url: URL(fileURLWithPath: entry.lastKnownPath)) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(entry.lastKnownPath,
                                              inFileViewerRootedAtPath: "")
            }
        }
    }

    private func row(url: URL, icon: String, label: String, tint: Color?, canPin: Bool) -> some View {
        SidebarItemRow(icon: icon, label: label, tint: tint)
            .contentShape(Rectangle())
            .onTapGesture { app.navigateUnscoped(to: url) }
            .contextMenu {
                if canPin {
                    if app.bookmarks.isPinned(url: url) {
                        Button("Unpin") { try? app.bookmarks.togglePin(url: url) }
                    } else {
                        Button("Add to Pinned") { try? app.bookmarks.togglePin(url: url) }
                    }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(url.path,
                                                  inFileViewerRootedAtPath: "")
                }
            }
    }

    private func locationLabel(_ url: URL) -> String {
        if url.path == "/" {
            return Host.current().localizedName ?? "Computer"
        }
        return url.lastPathComponent
    }
}
```

- [ ] **Step 3: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. 아직 ContentView 에 연결 안 되었으니 UI 는 변화 없음.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Sidebar/SidebarItemRow.swift apps/Sources/Views/Sidebar/SidebarView.swift
git commit -m "feat(sidebar): add SidebarView (4 sections) + SidebarItemRow"
```

---

## Task 7: `BreadcrumbBar`

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/BreadcrumbBar.swift`

현재 폴더의 경로 세그먼트를 toolbar horizontal 바로 렌더. 각 세그먼트 클릭 → 해당 경로로 `navigateUnscoped`.

- [ ] **Step 1: 파일 작성**

```swift
import SwiftUI

/// Path segments for the current folder, rendered as clickable buttons.
/// Lives inside ContentView's toolbar. "Computer" slash is represented as a
/// single leading "/" segment.
struct BreadcrumbBar: View {
    @Bindable var app: AppModel

    var body: some View {
        if let current = app.currentFolder {
            HStack(spacing: 2) {
                ForEach(Array(segments(for: current).enumerated()), id: \.offset) { pair in
                    let (i, seg) = pair
                    Button(seg.label) { app.navigateUnscoped(to: seg.url) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(i == segments(for: current).count - 1 ? Color.primary : Color.secondary)
                    if i < segments(for: current).count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func segments(for url: URL) -> [(label: String, url: URL)] {
        var out: [(String, URL)] = []
        let components = url.standardizedFileURL.pathComponents
        var accum = URL(fileURLWithPath: "/")
        for (i, c) in components.enumerated() {
            if i == 0 { continue } // first is "/"
            accum = accum.appendingPathComponent(c)
            out.append((c, accum))
        }
        // Leading "/" segment — shows as "Computer".
        let rootLabel = Host.current().localizedName ?? "Computer"
        out.insert((rootLabel, URL(fileURLWithPath: "/")), at: 0)
        return out
    }
}
```

- [ ] **Step 2: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/BreadcrumbBar.swift
git commit -m "feat(breadcrumb): add BreadcrumbBar toolbar item"
```

---

## Task 8: `FileListCoordinator` 에 우클릭 메뉴 추가

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

NSTableView 행 우클릭 → "Add to Pinned" (폴더에만 노출, 이미 pinned 면 비활성 / "Unpin"). "Reveal in Finder" 는 일관성 위해 모두에 표시.

Coordinator 는 현재 pin 상태 판정을 위해 `bookmarks` 레퍼런스가 필요. 기존 생성자에 `bookmarks` 주입을 추가 — `FileListView.makeCoordinator()` 에서 `app.bookmarks` 도 같이 넘겨야 함. 따라서 `FileListView` 에도 `@Bindable var app: AppModel` (또는 `bookmarks` 직접) 을 주입하는 쪽이 깔끔.

간단화: Coordinator 에 `onAddToPinned: (FileEntry) -> Void` 콜백 하나를 더 주입. Pin 판정은 콜백 안에서 수행 (ContentView 쪽이 app 접근 가능). 이게 가장 decoupled.

- [ ] **Step 1: `FileListCoordinator.swift` 수정 — `onAddToPinned` 주입**

먼저 `init` 시그니처 확장:

기존:
```swift
    init(folder: FolderModel, onActivate: @escaping (FileEntry) -> Void) {
        self.folder = folder
        self.onActivate = onActivate
        super.init()
    }
```

다음으로 교체:
```swift
    private let onAddToPinned: (FileEntry) -> Void
    private let isPinnedCheck: (FileEntry) -> Bool

    init(folder: FolderModel,
         onActivate: @escaping (FileEntry) -> Void,
         onAddToPinned: @escaping (FileEntry) -> Void,
         isPinnedCheck: @escaping (FileEntry) -> Bool) {
        self.folder = folder
        self.onActivate = onActivate
        self.onAddToPinned = onAddToPinned
        self.isPinnedCheck = isPinnedCheck
        super.init()
    }
```

- [ ] **Step 2: 동일 파일 — `tableView(_:menuForEvent:)` 추가**

클래스 끝부분 (`private func sortField` 위) 에 다음을 추가:

```swift
    // MARK: - Right-click menu

    /// Called by NSTableView when user right-clicks. Returns a menu customized
    /// for the clicked row. For file rows we only surface "Reveal in Finder";
    /// folders get pin management as well.
    func tableView(_ tableView: NSTableView, menuForEvent event: NSEvent) -> NSMenu? {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)
        guard row >= 0, row < lastSnapshot.count else { return nil }
        let entry = lastSnapshot[row]

        let menu = NSMenu()

        if entry.kind == .Directory {
            let item = NSMenuItem(
                title: isPinnedCheck(entry) ? "Unpin" : "Add to Pinned",
                action: #selector(menuAddToPinned(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = entry
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let reveal = NSMenuItem(title: "Reveal in Finder",
                                action: #selector(menuRevealInFinder(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = entry
        menu.addItem(reveal)

        return menu
    }

    @objc private func menuAddToPinned(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        onAddToPinned(entry)
    }

    @objc private func menuRevealInFinder(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        NSWorkspace.shared.selectFile(entry.path.toString(),
                                      inFileViewerRootedAtPath: "")
    }
```

- [ ] **Step 3: `FileListView.swift` — coordinator 생성 시 callbacks 주입**

기존:
```swift
    func makeCoordinator() -> FileListCoordinator {
        FileListCoordinator(folder: folder, onActivate: onActivate)
    }
```

다음으로 교체:

```swift
    let onAddToPinned: (FileEntry) -> Void
    let isPinnedCheck: (FileEntry) -> Bool

    func makeCoordinator() -> FileListCoordinator {
        FileListCoordinator(folder: folder,
                            onActivate: onActivate,
                            onAddToPinned: onAddToPinned,
                            isPinnedCheck: isPinnedCheck)
    }
```

그리고 `struct FileListView: NSViewRepresentable { ... }` 의 저장 프로퍼티 블록에 두 신규 필드를 선언 — 위치는 `let onActivate: (FileEntry) -> Void` 바로 아래.

- [ ] **Step 4: 빌드 (아직 ContentView 는 예전 시그니처로 호출 중 → 컴파일 에러 예상)**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:" | head -5
```

Expected: ContentView 의 `FileListView(folder:onActivate:)` 호출부에서 `Missing arguments for parameters 'onAddToPinned', 'isPinnedCheck'`. Task 9 에서 해결. 다른 종류 에러 있으면 STOP.

- [ ] **Step 5: 커밋 (WIP — ContentView Task 9 에서 마무리)**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift apps/Sources/Views/FileList/FileListView.swift
git commit -m "feat(file-list): add right-click menu with Add to Pinned + Reveal in Finder (WIP)"
```

---

## Task 9: `ContentView` — 3-pane wire-up + empty state 제거 + `⌘D` + `onAddToPinned`

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift`

`OpenFolderEmptyState` 분기 제거. 사이드바 + 브레드크럼 + 프리뷰 placeholder 를 `NavigationSplitView` 에 연결. `⌘D` 토글. `currentFolder` 변화 시 `lastFolder.save`. `FileListView` 의 신규 콜백 2 개 주입.

- [ ] **Step 1: `ContentView.swift` 전체 교체**

```swift
import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var folder: FolderModel?

    var body: some View {
        @Bindable var app = app
        return NavigationSplitView {
            SidebarView(app: app)
        } content: {
            if let folder {
                FileListView(
                    folder: folder,
                    onActivate: handleOpen,
                    onAddToPinned: handleAddToPinned,
                    isPinnedCheck: { entry in
                        app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
                    }
                )
            } else {
                ProgressView().controlSize(.small)
            }
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
            ToolbarItem(placement: .principal) {
                BreadcrumbBar(app: app)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { app.toggleCurrentFolderPin() }) {
                    Image(systemName: pinIconName)
                }
                .help(app.currentFolder.map(app.bookmarks.isPinned) == true ? "Unpin current folder" : "Pin current folder")
                .keyboardShortcut("d", modifiers: [.command])
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
            app.lastFolder.save(url)
            Task { await folder?.load(url) }
        }
    }

    private var pinIconName: String {
        guard let url = app.currentFolder else { return "pin" }
        return app.bookmarks.isPinned(url: url) ? "pin.fill" : "pin"
    }

    private func ensureFolderModel() {
        if folder == nil { folder = FolderModel(engine: app.engine) }
    }

    private func handleOpen(_ entry: FileEntry) {
        let url = URL(fileURLWithPath: entry.path.toString())
        if entry.kind == .Directory {
            app.history.push(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleAddToPinned(_ entry: FileEntry) {
        guard entry.kind == .Directory else { return }
        let url = URL(fileURLWithPath: entry.path.toString())
        try? app.bookmarks.togglePin(url: url)
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

- [ ] **Step 2: 빌드 — `** BUILD SUCCEEDED **`**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

에러 있으면 STOP.

- [ ] **Step 3: 테스트 regression 통과 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 17/17.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ContentView.swift
git commit -m "feat(app): wire sidebar + breadcrumb + default landing; remove empty-state gate"
```

---

## Task 10: `OpenFolderEmptyState` 삭제

**Files:**
- Delete: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Onboarding/OpenFolderEmptyState.swift`

Task 9 이후로 사용처 없음. 디렉터리도 빈 채 남지 않도록 같이 정리.

- [ ] **Step 1: 사용처 없음 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
grep -r "OpenFolderEmptyState" apps/ --include="*.swift" | grep -v Generated
```

Expected: 출력 없음 (있으면 STOP).

- [ ] **Step 2: 파일 삭제 + 디렉터리 정리**

```bash
cd /Users/cyj/workspace/personal/cairn
rm apps/Sources/Views/Onboarding/OpenFolderEmptyState.swift
# 디렉터리가 비었으면 그것도 제거
rmdir apps/Sources/Views/Onboarding 2>/dev/null || true
```

- [ ] **Step 3: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add -A apps/Sources/Views/Onboarding apps/Sources/Views
git commit -m "chore(onboarding): remove OpenFolderEmptyState gate (default landing replaces it)"
```

---

## Task 11: 수동 E2E 검증 (사용자 직접 수행)

**Files:** 없음 (검증만)

M1.2 와 동일하게 사용자가 직접 체크. 서브에이전트는 앱만 빌드해 두고 기다릴 것.

- [ ] **Step 1: 앱 빌드 준비**

```bash
cd /Users/cyj/workspace/personal/cairn
./scripts/build-rust.sh
./scripts/gen-bindings.sh
cd apps && xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
echo "APP: $APP"
open "$APP"
```

- [ ] **Step 2: 체크리스트 (사용자 수행)**

- [ ] 첫 실행 → empty state **안 뜨고**, Home 디렉터리가 바로 렌더
- [ ] 앱 종료 후 다른 폴더로 `⌘↑` / 하위 진입 / `⌘←→` 후 재실행 → 마지막 폴더로 복원
- [ ] 사이드바에 **Pinned** 섹션 (처음엔 hidden, 핀 추가하면 노출)
- [ ] 사이드바에 **Recent** 섹션 (처음엔 hidden, `⌘O` 로 폴더 열어보면 노출)
- [ ] iCloud 가 설정된 시스템이라면 **iCloud Drive** 항목 표시 / 없으면 섹션 자체 미표시
- [ ] **Locations** 섹션에 "Computer" (루트) + 마운트된 외장 볼륨
- [ ] `⌘D` → 현재 폴더 Pinned 섹션에 즉시 추가, 핀 아이콘 `pin` → `pin.fill` 변화, 한 번 더 누르면 제거
- [ ] 파일 리스트 폴더 행 우클릭 → "Add to Pinned" / "Reveal in Finder"
- [ ] 파일 행 우클릭 → "Reveal in Finder" 만 (Pin 항목 없음)
- [ ] 외장 USB 꽂기 → Locations 즉시 반영 / 뽑기 → 즉시 제거
- [ ] BreadcrumbBar 세그먼트 클릭 → 해당 경로로 이동
- [ ] Pinned / Recent 사이드바 항목 클릭 → 해당 폴더 진입
- [ ] M1.2 기능 regression 없음 (컬럼 정렬, 다중 선택, ↑↓/⏎)

문제 발견 시 어떤 것이 안 되는지 메모하고 STOP.

- [ ] **Step 3: 커밋 불필요 — 검증만**

---

## Task 12: 워크스페이스 sanity + tag

**Files:** 없음 (검증 + tag)

- [ ] **Step 1: 로컬 CI 시뮬레이션**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./scripts/build-rust.sh
./scripts/gen-bindings.sh
(cd apps && xcodegen generate && xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | tail -3)
(cd apps && xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | grep -E "Executed|TEST" | tail -5)
```

Expected: 모두 녹색. Swift 테스트 총 17 (기존 10 + MountObserver 1 + LastFolder 3 + Sidebar 3).

- [ ] **Step 2: fmt 가 실패하면 자동 정렬 + 별도 커밋**

```bash
cargo fmt --all
git diff --stat
# 변경 있으면:
git add -A crates/
git commit -m "style: cargo fmt"
```

- [ ] **Step 3: M1.3 완료 tag**

```bash
cd /Users/cyj/workspace/personal/cairn
git tag phase-1-m1.3
git log --oneline phase-1-m1.2..HEAD
```

Expected: M1.3 의 모든 커밋 (약 10 개).

---

## 🎯 M1.3 Definition of Done

- [ ] `MountObserver` — NSWorkspace mount/unmount 구독, `volumes: [URL]` 실시간 유지 + 1 unit test
- [ ] `LastFolderStore` — UserDefaults `cairn.lastFolderPath` save/load/clear + 3 unit test
- [ ] `SidebarModel` — iCloud URL 합성 + Locations 합성 (Computer + volumes) + MountObserver 구독 + 3 unit test
- [ ] `BookmarkStore.isPinned / togglePin` 추가
- [ ] `AppModel` — 디폴트 랜딩 부트스트랩 (lastFolder ?? Home), `navigateUnscoped`, `toggleCurrentFolderPin`, `sidebar` + `mountObserver` exposure
- [ ] `SidebarView` + `SidebarItemRow` — 4 섹션 렌더, 클릭 내비, 우클릭 Pin/Unpin/Reveal
- [ ] `BreadcrumbBar` — 경로 세그먼트 toolbar item
- [ ] `FileListCoordinator` 우클릭 메뉴 — Add to Pinned (폴더만) + Reveal in Finder (공통)
- [ ] `ContentView` — OpenFolderEmptyState 분기 제거, Sidebar + Breadcrumb 통합, `⌘D` 토글, lastFolder 저장
- [ ] `OpenFolderEmptyState` 삭제됨
- [ ] 앱 실행 → 즉시 3-pane, 마지막/기본 폴더 렌더
- [ ] `cargo test --workspace` + `cargo clippy -- -D warnings` + `xcodebuild build` + `xcodebuild test` 모두 녹색
- [ ] `git tag phase-1-m1.3` 존재

---

## M1.2 에서 이월된 follow-up (이 마일스톤에서 처리 안 함)

M1.2 code-review 에서 올라온 것들 중 M1.3 range 에 **속하지 않는** 것:
- `FileListCoordinator` 의 `sortDescriptorsDidChange` 내부 재진입 가드 범위 문서화 — **M1.5** (테마/리팩터 동반) 로 이월
- `@Bindable var folder` → `let folder` in `FileListView` — M1.5 — 이전에 SwiftUI 관찰 경로 재확인 필요
- `modified_unix == 0` sentinel 주석 — M1.4 (preview 추가 시 `FileEntry` 주변 주석 정리와 함께)
- `activateSelected()` 단일 행만 동작 — M1.5 (context menu 에 "Open" 추가할 때 같이)
- `import SwiftUI` unused in `FileListCoordinator.swift` — **M1.3 Task 8** 에서 자연스럽게 수정됨 (이 Task 에서 Coordinator 수정 시 unused import 남아있으면 제거)

---

## 다음 마일스톤 (스펙 § 11 요약, 2026-04-21 조정판)

| M | 범위 요약 | M1.3 결과로부터의 인풋 |
|---|---|---|
| **1.4** | `cairn-preview` Rust + 이미지 썸네일 + MetaOnly + `Space` Quick Look + `⌘⇧.` | `FolderModel.selection` 의 첫 항목이 PreviewModel 로 push. Sidebar selection 도 고려 (iCloud/Locations 항목 미리보기는 Phase 2). |
| **1.5** | `CairnTheme` 토큰 + Glass Blue 팔레트 + NSVisualEffectView + 파일 리스트 context menu 확장 (Copy Path / Move to Trash / Open With) | FileListCoordinator 의 menu delegate 는 이미 M1.3 에서 붙였으니 Theme + 메뉴 확장만 |
| **1.6** | E2E 완주 + README + `create-dmg` + `v0.1.0-alpha` + **signing + sandbox 재활성화** — 이 시점에 디폴트 랜딩이 sandbox 에서 정상인지 검증, 필요하면 first-launch NSOpenPanel (Home 프리포지션) 재도입 |

각 후속 마일스톤 플랜은 직전 M 완료 직후 작성.
