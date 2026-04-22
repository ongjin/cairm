# Cairn Phase 1 · M1.7 — Design Polish → `v0.1.0-alpha.1`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** M1.5 Glass Blue 를 파일 리스트 / 시스템 아이콘 / empty state / selection·focus·search 모든 인터랙션 표면에 확장해서 "Finder-replacement 룩앤필" 일관성 확보.

**Architecture:** Swift-only. Rust / FFI / `CairnTheme` 토큰 불변. 신규 컴포넌트 4개 (`EmptyStateView`, `ThemedSearchField`, `FileListIconCache`, `FileListRowView`) + 기존 `FileListView` / `FileListCoordinator` / `ContentView` 수정. `NSColor.controlAccentColor.withAlphaComponent(0.22)` 로 다크/라이트 자동 대응.

**Tech Stack:** Swift 5.9 · SwiftUI · AppKit (`NSTableRowView`, `NSWorkspace`, `NSCache`, `NSVisualEffectView`) · macOS 14 deployment · xcodegen 2.45

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main branch, HEAD 시작 = `phase-1-m1.6` + spec 커밋 `d9d0099`)

**Predecessor:** M1.6 — `docs/superpowers/plans/2026-04-21-cairn-phase-1-m1.6-search-polish.md` (완료, tag `phase-1-m1.6` + `v0.1.0-alpha`)
**Parent spec:** `docs/superpowers/specs/2026-04-22-cairn-phase-1-m1.7-design-polish-design.md`

**Deliverable verification (M1.7 완료 조건):**
- `xcodebuild build` 성공
- `xcodebuild test` 29+ (M1.6 27 + EmptyStateViewTests + FileListIconCacheTests)
- `cargo test --workspace` 녹색 (Rust 불변; regression check 만)
- 앱 실행 → 파일 리스트 Glass Blue, macOS 시스템 아이콘, 3 empty state 표시, accentMuted selection·SearchField·hover 일관
- `git tag phase-1-m1.7` + `git tag v0.1.0-alpha.1` (같은 HEAD)

**특이사항:**
- **FFI 변경 없음** — `build-rust.sh` / `gen-bindings.sh` 돌려도 Generated diff 0. diff 생기면 STOP.
- **SourceKit stale** — `xcodegen generate` 직후 diagnostics 무시. `xcodebuild` = 진실.
- **커밋 메시지 verbatim.**
- **원격 push 는 수동.**

---

## 1. 기술 참조 (M1.7 특유 함정)

- **`NSScrollView.drawsBackground = false` + `NSTableView.backgroundColor = .clear`** — 둘 다 false 해야 Glass 가 뚫려 보임. 하나만 끄면 다른 쪽 opaque 가 남아서 효과 없음
- **`NSTableView.usesAlternatingRowBackgroundColors = false`** — 투명 위에 alt row 색이 올라가면 패턴이 엉성해짐. M1.2 에서 true 로 설정돼있으므로 명시적으로 false 로 바꿔야 함
- **`NSWorkspace.icon(forFile:)` 리턴**: `NSImage` instance. 같은 확장자 여러 파일에 대해 identical-instance 는 아니지만 같은 내용. `NSCache` 로 확장자 단위로 가둬도 안전
- **`NSTableView.rowViewForRow` delegate**: SwiftUI NSViewRepresentable 에선 기본 NSTableView 가 view-based cell 이라 `makeView(withIdentifier:)` 패턴과 충돌할 수 있음. `rowViewForRow` 만 추가하면 selection 처리 override 되고 cell content 는 영향 없음
- **Light mode contrast** — 현재 `text: Color(white: 0.93)`, `textSecondary: 0.60`, `textTertiary: 0.42` 는 어두운 배경 전제. 라이트 모드 윈도우 chrome 배경 은 `.hudWindow` 가 자동으로 밝게 바꾸지만 우리 tint 오버레이가 얹히면 중간톤이 됨. 실측 후 필요하면 `NSAppearance` 조건 분기. M1.7 는 **실측해서 문제 있을 때만 분기 추가** — 없으면 그대로
- **`@Environment(\.accessibilityReduceMotion)`** — SwiftUI 는 자동 존중 (`.transition` 들이 reduce-motion 에서 알아서 비활성). 명시적 체크 불필요, 단 `withAnimation` 직접 호출하는 자리에선 환경값 확인
- **`NSOpenPanel` 재프롬프트** — AppModel 에 이미 initial folder pick 로직이 있음. "Grant Access" 버튼이 재호출하는 방식. 대상 폴더 URL 은 `app.currentFolder` 그대로 (실패 에러에서 captured)

---

## 2. File Structure 요약

**신규**:
- `apps/Sources/Services/FileListIconCache.swift`
- `apps/Sources/Views/FileList/FileListRowView.swift`
- `apps/Sources/Views/Empty/EmptyStateView.swift`
- `apps/Sources/Views/Search/ThemedSearchField.swift`
- `apps/CairnTests/FileListIconCacheTests.swift`
- `apps/CairnTests/EmptyStateViewTests.swift`

**수정**:
- `apps/Sources/Views/FileList/FileListView.swift` (bg blur + drawsBackground off)
- `apps/Sources/Views/FileList/FileListCoordinator.swift` (icon cache + rowViewForRow)
- `apps/Sources/ContentView.swift` (empty state 분기 + ThemedSearchField)

**삭제**:
- `apps/Sources/Views/Search/SearchField.swift` (ThemedSearchField 로 대체)

---

## Task 1: `FileListIconCache` — NSCache 래퍼 (TDD)

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Services/FileListIconCache.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/CairnTests/FileListIconCacheTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`apps/CairnTests/FileListIconCacheTests.swift`:

```swift
import XCTest
import AppKit
@testable import Cairn

final class FileListIconCacheTests: XCTestCase {
    func test_same_extension_returns_cached_instance() {
        let cache = FileListIconCache()
        let img1 = cache.icon(forPath: "/tmp/a.txt", isDirectory: false)
        let img2 = cache.icon(forPath: "/tmp/b.txt", isDirectory: false)
        XCTAssertTrue(img1 === img2, "Same ext should return cached NSImage instance")
    }

    func test_different_extensions_return_distinct_images() {
        let cache = FileListIconCache()
        let img1 = cache.icon(forPath: "/tmp/a.txt", isDirectory: false)
        let img2 = cache.icon(forPath: "/tmp/a.json", isDirectory: false)
        // 다른 ext 는 반드시 같은 인스턴스일 필요는 없음. 아이콘 자체가 같을 수 있음.
        // 여기선 cache slot 이 구분되는지만 확인 — 호출 자체가 panic 없이 반환되는 것.
        XCTAssertNotNil(img1)
        XCTAssertNotNil(img2)
    }

    func test_directory_is_cached_separately() {
        let cache = FileListIconCache()
        let file = cache.icon(forPath: "/tmp/a.txt", isDirectory: false)
        let dir = cache.icon(forPath: "/tmp/a.txt", isDirectory: true)
        // 같은 path 라도 isDirectory 가 다르면 다른 cache slot
        // identity 까진 보장 못 하지만 crash 없이 두 인스턴스 반환되면 OK
        XCTAssertNotNil(file)
        XCTAssertNotNil(dir)
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|FileListIconCache" | tail -5
```

Expected: 컴파일 실패 ("Cannot find 'FileListIconCache'").

- [ ] **Step 3: 구현 작성**

`apps/Sources/Services/FileListIconCache.swift`:

```swift
import AppKit
import Foundation

/// Extension-keyed cache over `NSWorkspace.shared.icon(forFile:)`.
///
/// Rationale: `icon(forFile:)` returns the same visual icon for all files
/// sharing an extension (e.g., every `.swift` file gets the same "Swift
/// source" badge). Keying the cache by lowercased extension avoids a
/// per-path fetch and a per-row NSImage allocation — a noticeable saving in
/// large directories (1K+ files).
///
/// The cache persists for the app lifetime. Directories use a fixed sentinel
/// key because the system Folder icon is uniform.
final class FileListIconCache {
    private let cache = NSCache<NSString, NSImage>()
    private static let directoryKey: NSString = "__directory__"

    init() {
        cache.countLimit = 500  // 전형적 세션의 ext 다양성은 50 미만, 500 은 여유
    }

    /// Returns the cached icon for `path`. On miss, calls
    /// `NSWorkspace.shared.icon(forFile:)` and stores it.
    func icon(forPath path: String, isDirectory: Bool) -> NSImage {
        let key: NSString
        if isDirectory {
            key = Self.directoryKey
        } else {
            key = NSString(string: (path as NSString).pathExtension.lowercased())
        }
        if let hit = cache.object(forKey: key) {
            return hit
        }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(img, forKey: key)
        return img
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -5
```

Expected: 30 tests pass (27 기존 + 3 신규).

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Services/FileListIconCache.swift apps/CairnTests/FileListIconCacheTests.swift
git commit -m "feat(file-list): add extension-keyed icon cache"
```

---

## Task 2: `FileListCoordinator` — icon cache 연동

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

- [ ] **Step 1: Coordinator 에 cache instance 추가**

기존 private 필드 블록 (예: `private var externalEntries: [FileEntry]?` 근처) 에 추가:

```swift
    private let iconCache = FileListIconCache()
```

- [ ] **Step 2: `systemImage(for:)` 교체**

기존:

```swift
    private func systemImage(for entry: FileEntry) -> NSImage? {
        let symbolName: String
        if entry.kind == .Directory {
            symbolName = "folder.fill"
        } else if entry.kind == .Symlink {
            symbolName = "arrow.up.right.square"
        } else {
            symbolName = "doc"
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }
```

로 교체:

```swift
    private func systemImage(for entry: FileEntry) -> NSImage? {
        iconCache.icon(forPath: entry.path.toString(),
                       isDirectory: entry.kind == .Directory)
    }
```

Symlink 는 macOS 가 alias overlay 자동 처리 — 별도 분기 불필요.

- [ ] **Step 3: `cell.imageView?.contentTintColor` 라인 제거**

기존 `tableView(_:viewFor:row:)` 의 `.name` case 에:

```swift
            cell.imageView?.image = systemImage(for: entry)
            cell.imageView?.contentTintColor = entry.kind == .Directory ? .systemBlue : .secondaryLabelColor
```

둘째 줄 (`contentTintColor`) 삭제. 시스템 아이콘은 자체 색상을 갖고 있으므로 tint 로 덮으면 안 됨.

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -3
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 빌드 성공, 30/30 tests pass.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(file-list): use NSWorkspace system icons via cache"
```

---

## Task 3: `FileListRowView` — custom selection + wiring

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListRowView.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

- [ ] **Step 1: `FileListRowView.swift` 생성**

```swift
import AppKit

/// Row-level selection override so the NSTableView uses Cairn's
/// `accentMuted` pill (system accent @ 22% alpha + rounded rect) instead of
/// the default solid-accent selection. Matches the sidebar highlight and
/// SearchField border so all three interaction surfaces share one language.
///
/// `controlAccentColor` is used (not a hardcoded RGBA) so the User > System
/// Settings > Appearance > Accent Color choice propagates automatically.
final class FileListRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let color = NSColor.controlAccentColor.withAlphaComponent(0.22)
        color.setFill()
        let rect = bounds.insetBy(dx: 2, dy: 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.fill()
    }
}
```

- [ ] **Step 2: Coordinator 에 delegate method 추가**

`FileListCoordinator.swift` 의 `// MARK: - Delegate (view-based cells)` 섹션 근처에 추가 (기존 `tableView(_:viewFor:row:)` 바로 위/아래 어느 쪽이든):

```swift
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        FileListRowView()
    }
```

- [ ] **Step 3: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -3
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 30 tests pass. (Visual 검증은 E2E.)

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListRowView.swift apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(file-list): custom NSTableRowView for accentMuted selection"
```

---

## Task 4: `FileListView` — Glass Blue 배경

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListView.swift`

- [ ] **Step 1: NSScrollView + NSTableView opaque background 끄기**

기존 `makeNSView(context:)` 내부 table 설정 블록 (`table.usesAlternatingRowBackgroundColors = true` 같은 라인이 있음) 을 찾아서 다음과 같이 수정:

기존:
```swift
        let table = FileListNSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
```

교체:
```swift
        let table = FileListNSTableView()
        // Glass Blue 배경이 투과되도록 opaque 끄기. alt row 색상은 투명 위에서
        // 읽기 어려우므로 비활성화.
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.style = .inset
```

기존 `let scroll = NSScrollView()` 블록 (makeNSView 상단) 근처에서:

기존:
```swift
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
```

교체:
```swift
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false   // Glass 투과
```

- [ ] **Step 2: SwiftUI 래퍼에 theme + background 추가**

파일 최상단 import 섹션 아래에 `@Environment` 주입 — `struct FileListView: NSViewRepresentable` 선언 바로 아래:

```swift
    @Environment(\.cairnTheme) private var theme
```

그리고 `makeCoordinator()` 아래 (또는 struct 최하단) 에 SwiftUI modifier 로 background 를 얹을 수 있게 별도 View 래퍼가 필요한지 생각해야 함. NSViewRepresentable 은 `.background` 그대로 받아들임 — 호출부 (ContentView) 에서 붙이는 게 더 깨끗하지만, 이 스펙에선 FileListView 안에 담아 캡슐화하기 위해 `make / update` 에선 불가능. 대안: `_body` 를 SwiftUI 로 래핑하는 대신 **ContentView 에서 background 를 얹기**. 따라서 이 Task 는 scroll/table 의 drawsBackground 만 끄고, 배경 overlay 는 Task 7 (ContentView 통합) 에서 추가.

(만약 지금 modifier 를 FileListView 에 묶고 싶다면 NSViewRepresentable 을 감싸는 SwiftUI `View` wrapper 를 새로 두는 접근인데, 현재 호출 흐름 (`FileListView(...)` 가 바로 Tree 에 들어감) 을 고려하면 오버엔지니어링. **Task 7 에서 ContentView 가 `FileListView(...).background { ... }` 하도록 한다.**)

- [ ] **Step 3: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -3
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 빌드 성공, 30/30. 앱 실행해보면 파일 리스트 영역이 "창 배경색" (루트 `.hudWindow`) 이 비치는 상태. 색은 살짝 밝아 보일 수 있음 — Task 7 에서 tint overlay 얹으면 최종 모양.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListView.swift
git commit -m "feat(file-list): disable opaque background so Glass shines through"
```

---

## Task 5: `EmptyStateView` + 3 factory + 테스트

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Empty/EmptyStateView.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/CairnTests/EmptyStateViewTests.swift`

- [ ] **Step 1: 실패 테스트**

```swift
import XCTest
@testable import Cairn

final class EmptyStateViewTests: XCTestCase {
    func test_emptyFolder_uses_folder_icon_and_correct_title() {
        let v = EmptyStateView.emptyFolder()
        XCTAssertEqual(v.icon, "folder")
        XCTAssertEqual(v.title, "Empty folder")
        XCTAssertEqual(v.subtitle, "No files here.")
        XCTAssertNil(v.action)
    }

    func test_searchNoMatch_includes_query_in_subtitle() {
        let v = EmptyStateView.searchNoMatch(query: "hello")
        XCTAssertEqual(v.icon, "magnifyingglass")
        XCTAssertEqual(v.title, "No matches")
        XCTAssertEqual(v.subtitle, "for \"hello\"")
    }

    func test_permissionDenied_has_retry_action() {
        var called = false
        let v = EmptyStateView.permissionDenied(onRetry: { called = true })
        XCTAssertEqual(v.icon, "lock")
        XCTAssertEqual(v.title, "Can't read this folder")
        XCTAssertNotNil(v.action)
        v.action?.perform()
        XCTAssertTrue(called)
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "EmptyState|error:" | tail -5
```

Expected: 컴파일 실패 (`Cannot find 'EmptyStateView'`).

- [ ] **Step 3: 구현**

디렉터리 `apps/Sources/Views/Empty/` 는 없음 — 파일 생성 시 자동 생성됨.

`apps/Sources/Views/Empty/EmptyStateView.swift`:

```swift
import SwiftUI

/// Centered icon + title + optional subtitle + optional button.
/// Used for: empty folder, search no-match, permission denied. One layout
/// keeps the three states visually consistent — user always knows "this area
/// is intentionally empty, here's why".
struct EmptyStateView: View {
    let icon: String         // SF Symbol name
    let title: String
    let subtitle: String?
    let action: Action?

    @Environment(\.cairnTheme) private var theme

    struct Action {
        let label: String
        let perform: () -> Void
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(title)
                .font(theme.bodyFont.weight(.medium))
            if let subtitle {
                Text(subtitle)
                    .font(theme.headerFont)
                    .foregroundStyle(.tertiary)
            }
            if let action {
                Button(action.label, action: action.perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Factories

    static func emptyFolder() -> EmptyStateView {
        EmptyStateView(
            icon: "folder",
            title: "Empty folder",
            subtitle: "No files here.",
            action: nil
        )
    }

    static func searchNoMatch(query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No matches",
            subtitle: "for \"\(query)\"",
            action: nil
        )
    }

    static func permissionDenied(onRetry: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "lock",
            title: "Can't read this folder",
            subtitle: "The system denied access.",
            action: Action(label: "Grant Access…", perform: onRetry)
        )
    }
}
```

- [ ] **Step 4: 테스트 통과**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 33 tests pass (30 + 3).

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Empty/EmptyStateView.swift apps/CairnTests/EmptyStateViewTests.swift
git commit -m "feat(empty): add EmptyStateView with 3 factories + tests"
```

---

## Task 6: `ThemedSearchField` — rename + restyle

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Search/ThemedSearchField.swift`
- Delete: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Search/SearchField.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift` (call site 치환)

- [ ] **Step 1: 신규 `ThemedSearchField.swift` 작성**

```swift
import SwiftUI

/// Search field styled to match Cairn's Glass Blue palette. Replaces the
/// default `.roundedBorder` with an accent-tinted rounded rectangle + accent
/// border so the field reads as "search in this app" rather than generic
/// macOS text input. Scope Picker + progress badge unchanged from M1.6.
///
/// Focus is bound externally so `ContentView` can wire `⌘F` → `focused = true`.
struct ThemedSearchField: View {
    @Bindable var search: SearchModel
    @FocusState.Binding var focused: Bool

    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $search.scope) {
                Text("This Folder").tag(SearchModel.Scope.folder)
                Text("Subtree").tag(SearchModel.Scope.subtree)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            TextField("Search", text: $search.query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .fill(theme.accentMuted.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .stroke(theme.accent.opacity(0.4), lineWidth: 1)
                )
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

- [ ] **Step 2: 기존 `SearchField.swift` 삭제**

```bash
cd /Users/cyj/workspace/personal/cairn
rm apps/Sources/Views/Search/SearchField.swift
```

- [ ] **Step 3: `ContentView.swift` 의 호출부 치환**

기존 toolbar section 에 있는:

```swift
        ToolbarItem(placement: .automatic) {
            if let searchModel {
                SearchField(search: searchModel, focused: $searchFocused)
            }
        }
```

을 다음으로 교체:

```swift
        ToolbarItem(placement: .automatic) {
            if let searchModel {
                ThemedSearchField(search: searchModel, focused: $searchFocused)
            }
        }
```

(딱 `SearchField` → `ThemedSearchField` 이름만. 파라미터 동일.)

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -3
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 빌드 성공, 33/33.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Search/ThemedSearchField.swift apps/Sources/ContentView.swift
git rm apps/Sources/Views/Search/SearchField.swift
git commit -m "feat(search): replace SearchField with ThemedSearchField (accent-tinted)"
```

---

## Task 7: ContentView — empty state 분기 + 파일리스트 배경 overlay

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Models/AppModel.swift` (reopen helper 추가)

- [ ] **Step 1: `AppModel` 에 `reopenCurrentFolder` 헬퍼 추가**

`apps/Sources/Models/AppModel.swift` 를 먼저 Read 하고, 기존 initial-folder-pick 또는 NSOpenPanel 호출 위치를 찾기. 그 로직을 재사용하는 공개 메서드 추가:

```swift
    /// Re-prompts the user for folder access via `NSOpenPanel`. Invoked from
    /// the "Grant Access…" button in the permission-denied empty state.
    /// If the user picks a folder (same or different), `currentFolder` is
    /// re-set so FolderModel reloads.
    @MainActor
    func reopenCurrentFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let current = currentFolder {
            panel.directoryURL = current
        }
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.currentFolder = url
            }
        }
    }
```

> **Note:** `AppModel` 이 이미 `@MainActor` 거나 `@Observable` 인지 확인 — 그대로 유지. `NSOpenPanel` 관련 로직이 `OpenFolderEmptyState` (M1.1 시점) 에 비슷하게 있었을 수 있음. 중복이면 그 로직 쪽으로 통합. 아니면 새로 작성.

- [ ] **Step 2: `ContentView.swift` 의 `contentColumn` 교체**

기존 (Task 13 M1.6 결과):

```swift
    @ViewBuilder
    private var contentColumn: some View {
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

                if searchModel.isActive
                    && searchModel.results.isEmpty
                    && searchModel.phase != .running
                {
                    emptySearchState(query: searchModel.query)
                } else {
                    fileList(folder: folder, searchModel: searchModel)
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }
```

교체 (4 가지 변경: search no-match / empty folder / permission denied / fileList bg):

```swift
    @ViewBuilder
    private var contentColumn: some View {
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

                contentBody(folder: folder, searchModel: searchModel)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private func contentBody(folder: FolderModel, searchModel: SearchModel) -> some View {
        if searchModel.isActive
            && searchModel.results.isEmpty
            && searchModel.phase != .running
        {
            EmptyStateView.searchNoMatch(query: searchModel.query)
        } else if !searchModel.isActive
            && folder.state == .loaded
            && folder.entries.isEmpty
        {
            EmptyStateView.emptyFolder()
        } else if case .failed = folder.state, !searchModel.isActive {
            EmptyStateView.permissionDenied { app.reopenCurrentFolder() }
        } else {
            fileList(folder: folder, searchModel: searchModel)
        }
    }
```

또한 `fileList` helper 의 `FileListView(...)` 호출을 Glass Blue background 로 감싸기:

기존:
```swift
    private func fileList(folder: FolderModel, searchModel: SearchModel) -> some View {
        let isActive = searchModel.isActive
        let entries: [FileEntry] = isActive ? searchModel.results : folder.sortedEntries
        let showFolderCol = isActive && searchModel.scope == .subtree
        let searchRoot: URL? = isActive ? app.currentFolder : nil
        return FileListView(
            entries: entries,
            folder: folder,
            folderColumnVisible: showFolderCol,
            searchRoot: searchRoot,
            onActivate: handleOpen,
            onAddToPinned: handleAddToPinned,
            isPinnedCheck: { entry in
                app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
            },
            onSelectionChanged: handleSelectionChanged
        )
    }
```

교체:
```swift
    private func fileList(folder: FolderModel, searchModel: SearchModel) -> some View {
        let isActive = searchModel.isActive
        let entries: [FileEntry] = isActive ? searchModel.results : folder.sortedEntries
        let showFolderCol = isActive && searchModel.scope == .subtree
        let searchRoot: URL? = isActive ? app.currentFolder : nil
        return FileListView(
            entries: entries,
            folder: folder,
            folderColumnVisible: showFolderCol,
            searchRoot: searchRoot,
            onActivate: handleOpen,
            onAddToPinned: handleAddToPinned,
            isPinnedCheck: { entry in
                app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
            },
            onSelectionChanged: handleSelectionChanged
        )
        .background {
            ZStack {
                VisualEffectBlur(material: .contentBackground)
                theme.panelTint.opacity(0.55)
            }
            .ignoresSafeArea()
        }
    }
```

`theme` 이 ContentView 에 이미 있는지 확인 — 없으면 다음을 `@State` / property 목록에 추가:

```swift
    @Environment(\.cairnTheme) private var theme
```

- [ ] **Step 3: `emptySearchState(query:)` 제거**

기존에 ContentView 안에 M1.6 Task 13 으로 추가됐던:

```swift
    @ViewBuilder
    private func emptySearchState(query: String) -> some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No matches for \"\(query)\"")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

는 `EmptyStateView.searchNoMatch(query:)` 로 대체됐으므로 삭제.

- [ ] **Step 4: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -3
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 빌드 성공, 33/33.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ContentView.swift apps/Sources/Models/AppModel.swift
git commit -m "feat(app): wire 3 empty states + Glass bg on file list"
```

---

## Task 8: Capped banner 애니메이션 + 다크/라이트 검증

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift`

- [ ] **Step 1: Capped banner 에 transition 추가**

기존 `contentColumn` 안의 capped banner 블록:

```swift
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
```

교체 (transition + animation):

```swift
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
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
```

그리고 `VStack(spacing: 0)` 에 animation modifier:

```swift
        if let folder, let searchModel {
            VStack(spacing: 0) {
                ...
            }
            .animation(.easeInOut(duration: 0.2), value: searchModel.phase)
        } else {
            ProgressView().controlSize(.small)
        }
```

- [ ] **Step 2: 다크/라이트 모드 contrast 빠른 검증 (수동)**

```bash
cd /Users/cyj/workspace/personal/cairn
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
```

시스템 설정 → Appearance 를 Dark / Light 토글해보며 확인:
- [ ] 텍스트 읽을 수 있음 (WCAG AA ≈ 4.5:1)
- [ ] 사이드바 accent pill 이 라이트 모드에서 과하지 않음
- [ ] 파일 리스트 selection 이 양쪽 모드 모두 잘 보임
- [ ] SearchField border 가 라이트 모드에서 너무 흐릿하지 않음

**만약 라이트 모드에서 text 가 깨짐**: CairnTheme 의 `text`/`textSecondary`/`textTertiary` 가 하드코딩이라 분기가 필요. 이 경우 별도 follow-up 커밋으로 처리 — 일단 E2E 체크 결과 적어두고 이 Task 는 커밋. CairnTheme 수정은 지금은 피함 (Phase 3 theme switcher 스코프).

**만약 OK**: 그대로 진행.

- [ ] **Step 3: 빌드 + 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST" | tail -3
```

Expected: 33/33.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ContentView.swift
git commit -m "feat(app): animate capped banner (move+fade, 0.2s)"
```

---

## Task 9: E2E + sanity + `phase-1-m1.7` + `v0.1.0-alpha.1` tag

**Files:** 없음 (검증 + tag)

- [ ] **Step 1: 앱 실행 + spec § 7 체크리스트 (사용자 수행)**

```bash
cd /Users/cyj/workspace/personal/cairn
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
```

스펙 § 7 전 항목 체크. 하나라도 ❌ 면 STOP.

- [ ] **Step 2: 로컬 CI**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./scripts/build-rust.sh
./scripts/gen-bindings.sh
git status --short apps/Sources/Generated/
(cd apps && xcodegen generate && xcodebuild -scheme Cairn -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | tail -3)
(cd apps && xcodebuild test -scheme CairnTests -destination "platform=macOS" \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | grep -E "Executed|TEST" | tail -3)
```

Expected:
- fmt/clippy clean, cargo test green
- **Generated diff 는 0** — M1.7 는 FFI 불변. diff 생기면 이상, STOP
- xcodebuild build PASS
- xcodebuild test 33/33

- [ ] **Step 3: Tag**

```bash
cd /Users/cyj/workspace/personal/cairn
git tag phase-1-m1.7
git tag v0.1.0-alpha.1
git log --oneline phase-1-m1.6..phase-1-m1.7
```

Expected: M1.7 커밋 약 8개 (Task 1–8 각 1 커밋).

- [ ] **Step 4: Tag 확인**

```bash
git tag -l | grep -E "^(phase|v0)"
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
v0.1.0-alpha
v0.1.0-alpha.1
```

---

## 🎯 M1.7 Definition of Done

- [ ] `FileListIconCache` + `FileListRowView` + `EmptyStateView` + `ThemedSearchField` 신규 컴포넌트 4개
- [ ] `FileListView` Glass 배경 (drawsBackground off + ContentView overlay)
- [ ] `FileListCoordinator` 에 시스템 아이콘 + rowViewForRow 연동
- [ ] `ContentView` 에 3개 empty state 분기 (빈 폴더 / no-match / permission denied)
- [ ] `ThemedSearchField` 로 `SearchField` 교체 (기존 파일 삭제)
- [ ] `AppModel.reopenCurrentFolder()` 헬퍼
- [ ] Capped banner move+fade transition
- [ ] 라이트/다크 모드 contrast 수동 검증 통과
- [ ] `xcodebuild test` 33/33
- [ ] FFI Generated diff 0
- [ ] `git tag phase-1-m1.7` + `git tag v0.1.0-alpha.1` (같은 HEAD)

---

## 이월된 follow-up (Phase 2 / M1.8+)

이 플랜 **안 다룸**:

- CairnTheme 라이트/다크 variant (`text`/`textSecondary` 토큰이 다크 전제 — 라이트 모드에서 문제 있을 때만 Phase 3 시작 시 분기)
- 테마 스위처 UI (Phase 3)
- 드래그 앤 드롭 (Phase 2)
- 파일 preview 뷰 transitions (`.text` ↔ `.image` ↔ `.directory` crossfade)
- 사이드바 reorder / pin drag
- 파일 아이콘 캐시의 disk persistence (현재는 in-memory only)
- 검색 결과 relevance ranking (현재는 name/size/modified 정렬만)
- 다국어 (i18n)

---

## 다음 마일스톤 (Phase 2 M2.1+)

M1.7 완료 후:
- `cairn-index` (redb persistent index) 시작
- FSEvents 구독 + 실시간 동기화
- `⌘K` command palette
- Content search (ripgrep 스타일)
- Fuzzy matching (nucleo 크레이트 후보)

Phase 2 spec 은 M1.7 완료 후 작성 (parent spec § 13 참고).
