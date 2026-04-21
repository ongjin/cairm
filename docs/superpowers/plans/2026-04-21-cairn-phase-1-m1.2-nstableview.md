# Cairn Phase 1 · M1.2 — NSTableView File List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** M1.1 의 SwiftUI `List` 한 컬럼 placeholder 를 **NSTableView 기반 3-컬럼 (Name / Size / Modified) 파일 리스트** 로 교체한다. 헤더 클릭 정렬, 다중 선택, ↑↓/⏎ 키보드 네비, 더블클릭/⏎ 활성화까지. 컨텍스트 메뉴 · `⌘D` · `⌘R` · Quick Look 은 후속 마일스톤 (M1.3 ~ M1.5) 으로 이월.

**Architecture:** SwiftUI 와 AppKit 사이 `NSViewRepresentable` 어댑터를 두고 그 뒤에 NSScrollView + NSTableView (3 컬럼) 를 둔다. NSTableView 의 `dataSource` / `delegate` 는 단일 Coordinator 클래스가 양쪽을 구현. 정렬 상태 + 선택 상태는 `@Observable` `FolderModel` 이 소유 — Coordinator 는 `FolderModel` 을 단방향 미러링 (양방향 sync 는 Coordinator 가 selection/sortDescriptor 변경 시 FolderModel 에 push, FolderModel 변경 시 `updateNSView` 가 NSTableView 에 push). 행 정렬은 Swift 쪽에서 수행 (Rust walker 의 default sort 는 무시하고 매번 sortDescriptor 적용) — 10K 엔트리까지는 Swift 정렬로 충분하다는 가정 (Phase 2 에서 측정 후 필요하면 Rust 로 푸시).

**Tech Stack:** Swift 5.9 · SwiftUI · AppKit (NSScrollView, NSTableView, NSTableColumn, NSSortDescriptor, NSResponder) · `@Observable` · macOS 14+ · 기존 `cairn-walker` / `cairn-ffi` (변경 없음)

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main branch, M1.1 완료 상태. 시작 시점 HEAD 는 `phase-1-m1.1` 태그)

**Predecessor:** M1.1 — `docs/superpowers/plans/2026-04-21-cairn-phase-1-m1.1-walker-foundation.md` (완료)
**Parent spec:** `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md` § 11 M1.2 줄

**Deliverable verification (M1.2 완료 조건):**
- `cargo test --workspace` 녹색 (변경 없음, regression check)
- `xcodebuild -scheme Cairn build` 성공
- `xcodebuild test -scheme CairnTests` 녹색 — 신규 `FolderModelTests` 통과 (≥ 4 케이스)
- 앱 실행 → 폴더 진입 시 NSTableView 가 3 컬럼으로 렌더, header 클릭으로 정렬 토글, ⇧+클릭/⌘+클릭 다중 선택, ↑↓ 키 이동, ⏎ 또는 더블클릭으로 폴더 진입 / 파일 열기 작동
- `git tag phase-1-m1.2` 로 기준점

---

## 1. 기술 참조 (스택 경계만)

이 마일스톤 특유의 함정 위주.

- **NSViewRepresentable 두 단계 sync** — `makeNSView` 는 한 번만, `updateNSView` 는 SwiftUI 가 여러 번 호출. `updateNSView` 안에서 NSTableView 의 sortDescriptor / selectedRowIndexes 를 무조건 set 하면 Coordinator 의 콜백이 다시 발화 → 무한 재진입. 회피: Coordinator 의 `isApplyingModelUpdate` 플래그로 콜백 무시.
- **NSTableView 의 sortDescriptors API 는 `NSSortDescriptor`** — Swift 의 `SortDescriptor<T>` 와 다름. NSSortDescriptor 의 `key` 문자열로 컬럼을 식별 (`"name"`, `"size"`, `"modified"`).
- **`@Observable` 객체를 Coordinator 가 잡고 있을 때** — Coordinator 가 init 시 받은 인스턴스를 그대로 들고 있다. SwiftUI 의 view-state diff 와 무관하게 동일 인스턴스를 유지하므로 `updateNSView` 에서 reference 가 바뀌는 일은 없음 (FolderModel 은 ContentView 의 `@State`).
- **NSTableView 키보드 네비** — `↑/↓` 는 NSTableView 가 자동 처리. `↵`/`Enter` 는 직접 처리해야 — `keyDown(with:)` 오버라이드해서 `36` (Return) / `76` (Enter) 키코드 잡고 delegate 의 activate 호출.
- **`NSTableViewSelectionDidChange` 알림 vs delegate 메서드 vs `selectedRowIndexes` KVO** — delegate 의 `tableViewSelectionDidChange(_:)` 가 표준. SwiftUI binding 처럼 매끄럽지 않으므로 delegate 안에서 `folder.setSelection(...)` 호출하는 패턴.
- **double-click action** — NSTableView 의 `doubleAction` + `target` 으로 wire (delegate 에 두지 않음). `target` 은 Coordinator, `action` 은 `#selector(handleDoubleClick)`.
- **ByteCountFormatter** — 기본 `.useAll` style. 디렉터리는 size 가 0 이므로 dash (`—`) 로 fallback.
- **DateFormatter** — short style (`yyyy-MM-dd HH:mm`) — 한국 / US 무관하게 정렬 가능. RelativeDateTimeFormatter 는 정렬 깨지므로 X.

---

## 2. File Structure

이 M1.2 에서 생성·수정될 파일.

**Swift (apps/Sources/):**
- Modify: `apps/Sources/ViewModels/FolderModel.swift` (sortDescriptor + selection 추가, sortedEntries 노출)
- Create: `apps/Sources/Views/FileList/FileListView.swift` (NSViewRepresentable shell)
- Create: `apps/Sources/Views/FileList/FileListNSTableView.swift` (NSTableView 서브클래스 — keyDown 처리)
- Create: `apps/Sources/Views/FileList/FileListCoordinator.swift` (single class implementing dataSource + delegate)
- Modify: `apps/Sources/ContentView.swift` (FileListSimpleView → FileListView 교체)
- Delete: `apps/Sources/Views/FileList/FileListSimpleView.swift` (M1.1 placeholder, 더 이상 안 씀)

**Swift tests (apps/CairnTests/):**
- Create: `apps/CairnTests/FolderModelTests.swift` (sort + selection 단위 테스트)

**Rust:** 변경 없음.

**참고**: Generated/, Cargo.toml, project.yml, entitlements, BookmarkStore 모두 변경 없음.

---

## Task 1: `FolderModel` — sortDescriptor + selection 도입 (TDD)

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ViewModels/FolderModel.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/CairnTests/FolderModelTests.swift`

`FolderModel` 은 현재 `entries` 와 `state` 만 노출. M1.2 는 두 책임을 추가:
1. **sortDescriptor** (`SortField` × `SortOrder`) — UI 가 헤더 클릭 시 set, model 이 `sortedEntries` 를 자동 재계산.
2. **selection** (`Set<String>` — `FileEntry.path.toString()` 를 ID 로) — UI 가 selection 변경 시 set, NSTableView 가 다시 selectedRowIndexes 로 미러.

NSTableView 와 결합하기 전에 **순수 데이터 단위로 단위 테스트** 가능하도록 sort + selection 로직을 모델에 가둔다.

- [ ] **Step 1: `FolderModelTests.swift` — 실패하는 테스트 작성**

`apps/CairnTests/FolderModelTests.swift` 생성:

```swift
import XCTest
@testable import Cairn

final class FolderModelTests: XCTestCase {
    /// FolderModel 단독 테스트는 CairnEngine 을 호출하지 않는 setEntries 헬퍼를 통해
    /// 직접 entries 를 주입한다. 실제 listDirectory 는 통합 테스트 (수동 E2E) 에서 검증.
    var model: FolderModel!

    override func setUpWithError() throws {
        // CairnEngine() 는 Rust new_engine() 만 호출하므로 사이드이펙트 없음.
        model = FolderModel(engine: CairnEngine())
    }

    private func mkEntry(_ name: String, size: UInt64, modified: Int64, kind: FileKind) -> FileEntry {
        FileEntry(
            path: "/tmp/\(name)",
            name: name,
            size: size,
            modified_unix: modified,
            kind: kind,
            is_hidden: false,
            icon_kind: kind == .Directory ? .Folder : .GenericFile
        )
    }

    func test_sortedEntries_default_is_dirs_first_name_asc() {
        let a = mkEntry("alpha.txt", size: 10, modified: 100, kind: .Regular)
        let z = mkEntry("zeta.txt",  size: 30, modified: 300, kind: .Regular)
        let dir = mkEntry("subdir",  size: 0,  modified: 200, kind: .Directory)
        model.setEntries([z, a, dir])

        let names = model.sortedEntries.map { $0.name.toString() }
        XCTAssertEqual(names, ["subdir", "alpha.txt", "zeta.txt"])
    }

    func test_sortedEntries_by_size_desc_keeps_dirs_first() {
        let a = mkEntry("a.txt", size: 100, modified: 100, kind: .Regular)
        let b = mkEntry("b.txt", size: 500, modified: 200, kind: .Regular)
        let dir = mkEntry("z_dir", size: 0, modified: 50, kind: .Directory)
        model.setEntries([a, b, dir])

        model.setSortDescriptor(.init(field: .size, order: .descending))
        let names = model.sortedEntries.map { $0.name.toString() }
        // 디렉토리 먼저, 그 다음 size 큰 순.
        XCTAssertEqual(names, ["z_dir", "b.txt", "a.txt"])
    }

    func test_sortedEntries_by_modified_asc() {
        let old = mkEntry("old.txt", size: 10, modified: 100, kind: .Regular)
        let new = mkEntry("new.txt", size: 10, modified: 999, kind: .Regular)
        let mid = mkEntry("mid.txt", size: 10, modified: 500, kind: .Regular)
        model.setEntries([new, mid, old])

        model.setSortDescriptor(.init(field: .modified, order: .ascending))
        let names = model.sortedEntries.map { $0.name.toString() }
        XCTAssertEqual(names, ["old.txt", "mid.txt", "new.txt"])
    }

    func test_setSelection_overwrites_previous() {
        let a = mkEntry("a", size: 1, modified: 1, kind: .Regular)
        let b = mkEntry("b", size: 1, modified: 1, kind: .Regular)
        model.setEntries([a, b])

        model.setSelection(["/tmp/a"])
        XCTAssertEqual(model.selection, ["/tmp/a"])
        model.setSelection(["/tmp/b"])
        XCTAssertEqual(model.selection, ["/tmp/b"])
    }

    func test_clear_resets_state_and_selection() {
        let a = mkEntry("a", size: 1, modified: 1, kind: .Regular)
        model.setEntries([a])
        model.setSelection(["/tmp/a"])
        model.clear()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        if case .idle = model.state {} else { XCTFail("state should be .idle after clear()") }
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

Expected: `Cannot find 'setEntries'`, `Cannot find 'sortedEntries'`, `Cannot find 'SortDescriptor'` 등 다수 컴파일 에러. TDD red 신호.

- [ ] **Step 3: `FolderModel.swift` 전체 교체 — sort + selection 추가**

`apps/Sources/ViewModels/FolderModel.swift` 전체 교체:

```swift
import Foundation
import Observation

/// Folder-scoped view model. One instance per currently-displayed folder.
///
/// Owns:
///   - `entries`  — raw output of the engine (Rust default order).
///   - `sortDescriptor` — user-driven Name/Size/Modified × asc/desc.
///   - `sortedEntries` — derived view (recomputed from entries + sortDescriptor).
///   - `selection` — set of FileEntry paths currently highlighted in the table.
///
/// Sort policy: directories always come first regardless of sort field, then
/// the chosen field within each group. Matches Finder convention and gives
/// stable behaviour when toggling sort columns.
@Observable
final class FolderModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum SortField: String, Equatable {
        case name
        case size
        case modified
    }

    enum SortOrder: Equatable {
        case ascending
        case descending
    }

    struct SortDescriptor: Equatable {
        var field: SortField
        var order: SortOrder

        static let `default` = SortDescriptor(field: .name, order: .ascending)
    }

    private(set) var entries: [FileEntry] = []
    private(set) var state: LoadState = .idle
    private(set) var sortDescriptor: SortDescriptor = .default
    /// Path strings of currently-selected entries.
    private(set) var selection: Set<String> = []

    private let engine: CairnEngine

    init(engine: CairnEngine) {
        self.engine = engine
    }

    /// Test/internal entry-point — bypasses the engine and lets unit tests
    /// inject a known fixture. Production code uses `load(_:)`.
    func setEntries(_ list: [FileEntry]) {
        entries = list
        state = .loaded
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
        selection = []
        state = .idle
    }

    func setSortDescriptor(_ desc: SortDescriptor) {
        sortDescriptor = desc
    }

    func setSelection(_ paths: Set<String>) {
        selection = paths
    }

    /// Computed view: entries with directories first, then the chosen sort
    /// field applied within each group. Recomputed every access — fine for the
    /// 10K-entry ceiling. Phase 2 should cache if it ever shows up in profiles.
    var sortedEntries: [FileEntry] {
        let dirs = entries.filter { $0.kind == .Directory }
        let files = entries.filter { $0.kind != .Directory }
        return Self.sort(dirs, by: sortDescriptor) + Self.sort(files, by: sortDescriptor)
    }

    private static func sort(_ list: [FileEntry], by desc: SortDescriptor) -> [FileEntry] {
        let asc = (desc.order == .ascending)
        switch desc.field {
        case .name:
            return list.sorted { lhs, rhs in
                let l = lhs.name.toString().lowercased()
                let r = rhs.name.toString().lowercased()
                return asc ? (l < r) : (l > r)
            }
        case .size:
            return list.sorted { lhs, rhs in
                asc ? (lhs.size < rhs.size) : (lhs.size > rhs.size)
            }
        case .modified:
            return list.sorted { lhs, rhs in
                asc ? (lhs.modified_unix < rhs.modified_unix)
                    : (lhs.modified_unix > rhs.modified_unix)
            }
        }
    }
}
```

- [ ] **Step 4: 테스트 재실행 — 5/5 통과 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: `** TEST SUCCEEDED **`. 신규 5 (FolderModel) + 4 (BookmarkStore) + 1 (Placeholder) = 10 통과.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ViewModels/FolderModel.swift apps/CairnTests/FolderModelTests.swift
git commit -m "feat(folder-model): add sortDescriptor + selection state with tests"
```

---

## Task 2: `FileListView.swift` — NSViewRepresentable shell

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListView.swift`

NSScrollView + NSTableView 의 SwiftUI 어댑터. Coordinator (Task 3) 가 dataSource/delegate 를 둘 다 구현. 이 파일은 view 만 만들고 Coordinator 에 연결.

`apps/Sources/Views/FileList/FileListView.swift` 는 M1.1 의 `FileListSimpleView.swift` 와 같은 디렉터리. SimpleView 는 Task 6 에서 삭제.

- [ ] **Step 1: 파일 작성**

```swift
import SwiftUI
import AppKit

/// SwiftUI adapter for the AppKit-based file list. Hosts an NSScrollView whose
/// document view is `FileListNSTableView` (3 columns, header sort, multi-select).
///
/// Two-way data flow:
///   - SwiftUI → NSTableView: `updateNSView` reapplies the model snapshot.
///   - NSTableView → SwiftUI: Coordinator pushes selection / sortDescriptor
///     changes back into FolderModel, which re-publishes via @Observable.
struct FileListView: NSViewRepresentable {
    @Bindable var folder: FolderModel
    /// Called when a row is activated (double-click or ⏎). The closure receives
    /// the FileEntry; the caller decides whether to push history or open in NSWorkspace.
    let onActivate: (FileEntry) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let table = FileListNSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        // 3 columns: name (with icon), size, modified.
        let nameCol = NSTableColumn(identifier: .name)
        nameCol.title = "Name"
        nameCol.minWidth = 180
        nameCol.width = 320
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        table.addTableColumn(nameCol)

        let sizeCol = NSTableColumn(identifier: .size)
        sizeCol.title = "Size"
        sizeCol.minWidth = 70
        sizeCol.width = 90
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        table.addTableColumn(sizeCol)

        let modCol = NSTableColumn(identifier: .modified)
        modCol.title = "Modified"
        modCol.minWidth = 140
        modCol.width = 180
        modCol.sortDescriptorPrototype = NSSortDescriptor(key: "modified", ascending: false)
        table.addTableColumn(modCol)

        // Coordinator wears both hats.
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        // Double-click activation. Coordinator handles ⏎ via the subclass's keyDown.
        table.target = context.coordinator
        table.doubleAction = #selector(FileListCoordinator.handleDoubleClick(_:))

        // Initial sort indicator on Name column.
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        // Subclass needs a back-pointer for ⏎ activation.
        table.activationHandler = { [weak coord = context.coordinator] in
            coord?.activateSelected()
        }

        context.coordinator.attach(table: table)
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? FileListNSTableView else { return }
        context.coordinator.applyModelSnapshot(table: table)
    }

    func makeCoordinator() -> FileListCoordinator {
        FileListCoordinator(folder: folder, onActivate: onActivate)
    }
}

extension NSUserInterfaceItemIdentifier {
    static let name = NSUserInterfaceItemIdentifier("col.name")
    static let size = NSUserInterfaceItemIdentifier("col.size")
    static let modified = NSUserInterfaceItemIdentifier("col.modified")
}
```

이 파일은 다음 두 타입 (`FileListNSTableView`, `FileListCoordinator`) 을 참조 — 컴파일은 Task 3, 4 다 끝난 뒤에야 통과한다. 이 Step 에선 빌드하지 말고 바로 다음 Task 로 넘어간다.

- [ ] **Step 2: 커밋 (WIP — 빌드 안 됨)**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListView.swift
git commit -m "feat(file-list): add NSViewRepresentable shell for NSTableView (WIP)"
```

빌드 안 되는 게 정상 — Task 3, 4 가 의존 타입 도입.

---

## Task 3: `FileListNSTableView.swift` — 키보드 활성화용 서브클래스

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListNSTableView.swift`

NSTableView 의 default keyDown 은 ↑↓ 만 처리. ⏎/Enter 는 직접 잡아야 함.

- [ ] **Step 1: 파일 작성**

```swift
import AppKit

/// NSTableView subclass that surfaces ⏎ / numpad-Enter as an activation event.
/// Default NSTableView passes those keys through to the responder chain, which
/// is what we want to *override* — Cairn treats Return on a selected row as
/// "open this entry" (folder enter or file open).
final class FileListNSTableView: NSTableView {
    /// Set by FileListView.makeNSView right after construction. Optional because
    /// the table briefly exists before the Coordinator attaches.
    var activationHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return (main keyboard), 76 = numpad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            activationHandler?()
            return
        }
        super.keyDown(with: event)
    }
}
```

- [ ] **Step 2: 빌드 시도 — 의존 타입 (`FileListCoordinator`) 미존재로 여전히 실패**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:" | head -5
```

Expected: `Cannot find 'FileListCoordinator' in scope`. Task 4 에서 해결. 다른 에러 있으면 STOP.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListNSTableView.swift
git commit -m "feat(file-list): add NSTableView subclass with Return-key activation"
```

---

## Task 4: `FileListCoordinator.swift` — DataSource + Delegate 통합

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

NSTableViewDataSource + NSTableViewDelegate 를 한 클래스에서 구현. NSTableCellView 는 view-based 라 cell view 를 직접 만든다.

세 가지 책임:
1. **rowCount + objectValue** — `folder.sortedEntries` 를 그대로 노출.
2. **viewFor row + column** — 컬럼별 NSTableCellView (Name 은 icon + label, Size/Modified 는 right-aligned label).
3. **change observers** — sortDescriptor 변경 → folder.setSortDescriptor; selection 변경 → folder.setSelection; ⏎ / 더블클릭 → onActivate.

`isApplyingModelUpdate` 플래그가 핵심 — `updateNSView` 가 NSTableView 의 sortDescriptors / selectedRowIndexes 를 set 하는 동안 NSTableView 가 발화하는 콜백을 무시해서 무한 재진입 방지.

- [ ] **Step 1: 파일 작성**

```swift
import AppKit
import SwiftUI

/// Bridges FolderModel ↔ NSTableView.
///
/// Single class implementing both NSTableViewDataSource and NSTableViewDelegate.
/// Holds:
///   - `folder` (the @Observable model)
///   - `onActivate` (SwiftUI closure for double-click / ⏎)
///   - `lastSnapshot` (cached sorted view to avoid recomputing inside dataSource)
///   - `isApplyingModelUpdate` (re-entrancy guard during updateNSView)
final class FileListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let folder: FolderModel
    private let onActivate: (FileEntry) -> Void

    private weak var table: FileListNSTableView?
    private var lastSnapshot: [FileEntry] = []
    private var isApplyingModelUpdate = false

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    init(folder: FolderModel, onActivate: @escaping (FileEntry) -> Void) {
        self.folder = folder
        self.onActivate = onActivate
        super.init()
    }

    func attach(table: FileListNSTableView) {
        self.table = table
        // Initial snapshot.
        applyModelSnapshot(table: table)
    }

    // MARK: - Snapshot application (called from updateNSView)

    /// Pulls the latest sortedEntries into NSTableView and re-applies the
    /// selection set, suppressing the delegate's selection-change callback.
    func applyModelSnapshot(table: NSTableView) {
        isApplyingModelUpdate = true
        defer { isApplyingModelUpdate = false }

        lastSnapshot = folder.sortedEntries
        table.reloadData()

        // Restore selection (path-based).
        let indexes = NSMutableIndexSet()
        for (i, entry) in lastSnapshot.enumerated() {
            if folder.selection.contains(entry.path.toString()) {
                indexes.add(i)
            }
        }
        table.selectRowIndexes(indexes as IndexSet, byExtendingSelection: false)

        // Reflect sortDescriptor in column headers (visual indicator).
        let nsDesc = NSSortDescriptor(
            key: keyString(for: folder.sortDescriptor.field),
            ascending: folder.sortDescriptor.order == .ascending
        )
        if table.sortDescriptors != [nsDesc] {
            table.sortDescriptors = [nsDesc]
        }
    }

    // MARK: - DataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        lastSnapshot.count
    }

    // MARK: - Delegate (view-based cells)

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let column, row < lastSnapshot.count else { return nil }
        let entry = lastSnapshot[row]
        let identifier = column.identifier
        let cellId = NSUserInterfaceItemIdentifier("cell.\(identifier.rawValue)")

        let cell = (tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView)
            ?? makeCell(identifier: cellId, kind: identifier)

        switch identifier {
        case .name:
            cell.imageView?.image = systemImage(for: entry)
            cell.imageView?.contentTintColor = entry.kind == .Directory ? .systemBlue : .secondaryLabelColor
            cell.textField?.stringValue = entry.name.toString()
            cell.textField?.alignment = .left
        case .size:
            cell.textField?.stringValue = entry.kind == .Directory
                ? "—"
                : byteFormatter.string(fromByteCount: Int64(entry.size))
            cell.textField?.alignment = .right
        case .modified:
            let date = Date(timeIntervalSince1970: TimeInterval(entry.modified_unix))
            cell.textField?.stringValue = entry.modified_unix == 0 ? "—" : dateFormatter.string(from: date)
            cell.textField?.alignment = .right
        default:
            cell.textField?.stringValue = ""
        }
        return cell
    }

    // MARK: - Sort

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if isApplyingModelUpdate { return }
        guard let new = tableView.sortDescriptors.first,
              let key = new.key,
              let field = sortField(for: key) else { return }

        let order: FolderModel.SortOrder = new.ascending ? .ascending : .descending
        folder.setSortDescriptor(.init(field: field, order: order))
        // Reapply snapshot to re-sort + restore selection.
        applyModelSnapshot(table: tableView)
    }

    // MARK: - Selection

    func tableViewSelectionDidChange(_ notification: Notification) {
        if isApplyingModelUpdate { return }
        guard let table = notification.object as? NSTableView else { return }
        let paths = table.selectedRowIndexes.compactMap { row -> String? in
            guard row < lastSnapshot.count else { return nil }
            return lastSnapshot[row].path.toString()
        }
        folder.setSelection(Set(paths))
    }

    // MARK: - Activation (double-click + ⏎)

    @objc func handleDoubleClick(_ sender: Any?) {
        guard let table = sender as? NSTableView else { return }
        let row = table.clickedRow
        guard row >= 0, row < lastSnapshot.count else { return }
        onActivate(lastSnapshot[row])
    }

    /// Called by FileListNSTableView's keyDown when ⏎ / Enter is pressed.
    func activateSelected() {
        guard let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, row < lastSnapshot.count else { return }
        onActivate(lastSnapshot[row])
    }

    // MARK: - Private helpers

    private func makeCell(identifier: NSUserInterfaceItemIdentifier, kind: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.font = .systemFont(ofSize: 12)
        textField.cell?.usesSingleLineMode = true
        cell.addSubview(textField)
        cell.textField = textField

        if kind == .name {
            // Name column gets an icon + label.
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

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

    private func keyString(for field: FolderModel.SortField) -> String {
        switch field {
        case .name: return "name"
        case .size: return "size"
        case .modified: return "modified"
        }
    }

    private func sortField(for key: String) -> FolderModel.SortField? {
        switch key {
        case "name": return .name
        case "size": return .size
        case "modified": return .modified
        default: return nil
        }
    }
}
```

- [ ] **Step 2: 빌드 시도 — 컴파일 통과 (앱은 아직 SimpleView 사용 중)**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. ContentView 는 아직 FileListSimpleView 사용 중. Task 5 에서 swap.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(file-list): add Coordinator with 3-column dataSource/delegate"
```

---

## Task 5: `ContentView` — `FileListSimpleView` → `FileListView` 교체

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift`

`handleOpen` 의 시그니처는 변경 없음 — `FileListView.onActivate` 도 `(FileEntry) -> Void` 로 동일.

- [ ] **Step 1: `ContentView.swift` 의 `content:` 클로저 줄 교체**

`apps/Sources/ContentView.swift` 안에서 다음 한 줄:

```swift
                } content: {
                    FileListSimpleView(folder: folder, onOpen: handleOpen)
                } detail: {
```

을 다음으로 교체:

```swift
                } content: {
                    FileListView(folder: folder, onActivate: handleOpen)
                } detail: {
```

(파라미터 라벨이 `onOpen` → `onActivate` 로 바뀐 점 주의 — `FileListView` 가 `onActivate` 라벨을 사용.)

`handleOpen` 함수 자체는 변경 없음. 다른 곳도 그대로.

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
git add apps/Sources/ContentView.swift
git commit -m "feat(app): swap FileListSimpleView for NSTableView-backed FileListView"
```

---

## Task 6: `FileListSimpleView.swift` 제거

**Files:**
- Delete: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListSimpleView.swift`

M1.1 placeholder. Task 5 이후로 어디서도 안 씀.

- [ ] **Step 1: 파일 삭제 + 사용처 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
grep -r "FileListSimpleView" apps/ --include="*.swift" | grep -v Generated
```

Expected: 출력 없음 (Task 5 의 swap 이 마지막 참조). 만약 출력 있으면 STOP.

- [ ] **Step 2: 삭제**

```bash
rm apps/Sources/Views/FileList/FileListSimpleView.swift
```

- [ ] **Step 3: 빌드 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

`FileEntry: Identifiable` extension 도 SimpleView 와 함께 사라짐 — 다른 곳에서 안 쓰는지 같은 grep 으로 확인 (Coordinator 는 path 를 직접 String 으로 다루므로 `.id` 불필요). 만약 누가 `FileEntry.ID` 를 참조하면 그 사용처도 수정 필요.

```bash
grep -rn "FileEntry\.ID\|\.id" apps/Sources --include="*.swift" | grep -v Generated | head
```

Expected: 거의 없음. 있으면 사용처 검토.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add -A apps/Sources/Views/FileList
git commit -m "chore(file-list): remove M1.1 FileListSimpleView placeholder"
```

---

## Task 7: 수동 E2E 검증

**Files:** 없음 (검증만)

- [ ] **Step 1: 앱 실행**

```bash
cd /Users/cyj/workspace/personal/cairn
./scripts/build-rust.sh
./scripts/gen-bindings.sh
cd apps && xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
```

- [ ] **Step 2: 체크리스트 통과 확인**

각 항목을 직접 눌러서 확인.

- [ ] 폴더 열기 → 3 컬럼 (Name / Size / Modified) 모두 헤더에 표시
- [ ] 디렉터리 행 → folder.fill 아이콘 (파란), Size 컬럼은 "—"
- [ ] 파일 행 → doc 아이콘, Size 컬럼은 ByteCountFormatter 출력 (예: `12 KB`)
- [ ] Modified 컬럼 → `yyyy-MM-dd HH:mm` 형식
- [ ] **Name 헤더 클릭** → 정렬 방향 토글 (asc ↔ desc), 디렉터리는 항상 위에 유지
- [ ] **Size 헤더 클릭** → size 정렬 (디렉터리 위, 그 다음 size 순)
- [ ] **Modified 헤더 클릭** → modified 정렬
- [ ] **단일 클릭** → 행 선택 (단일)
- [ ] **⇧+클릭** → range 다중 선택
- [ ] **⌘+클릭** → 토글 다중 선택
- [ ] **↑↓ 키** → 행 이동
- [ ] **⏎** → 선택된 폴더 진입 OR 파일은 NSWorkspace 로 열림
- [ ] **더블클릭** → 같은 동작
- [ ] **⌘← / ⌘→ / ⌘↑** → M1.1 의 히스토리 네비 그대로 작동

문제 발견 시 어떤 것이 안 되는지 메모하고 STOP.

- [ ] **Step 3: 커밋 불필요 — 검증만**

---

## Task 8: 워크스페이스 sanity + tag

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

Expected: 모두 녹색.

- [ ] **Step 2: fmt 가 실패하면 자동 정렬 + 별도 커밋**

```bash
cargo fmt --all
git diff --stat
# 변경 있으면:
git add -A crates/
git commit -m "style: cargo fmt"
```

- [ ] **Step 3: M1.2 완료 tag**

```bash
cd /Users/cyj/workspace/personal/cairn
git tag phase-1-m1.2
git log --oneline phase-1-m1.1..HEAD
```

Expected: M1.2 의 모든 커밋이 출력됨 (대략 6 ~ 8 개).

---

## 🎯 M1.2 Definition of Done

- [ ] `FolderModel` 가 `sortDescriptor` + `selection` 상태 노출, `sortedEntries` 가 dirs-first + 사용자 선택 정렬 정확히 적용
- [ ] `FileListView` (NSViewRepresentable) + `FileListNSTableView` + `FileListCoordinator` 3-파일 구조로 NSTableView 통합
- [ ] 3 컬럼 (Name w/ icon, Size formatted, Modified formatted) 렌더
- [ ] 헤더 클릭 → 정렬 방향 토글, 정렬 indicator 표시
- [ ] 다중 선택 (⇧/⌘ 클릭, ↑↓ shift) 가능, FolderModel.selection 에 path 단위로 반영
- [ ] ⏎ / 더블클릭 → onActivate 콜백 → ContentView 의 handleOpen 으로 폴더 진입 또는 파일 열기
- [ ] `FileListSimpleView` 삭제됨
- [ ] `FolderModelTests` 5개 + 기존 `BookmarkStoreTests` 4개 + `Placeholder` 1개 = 10/10 통과
- [ ] `cargo test --workspace` + `cargo clippy -- -D warnings` + `xcodebuild build` + `xcodebuild test` 모두 녹색
- [ ] `git tag phase-1-m1.2` 존재

---

## 다음 마일스톤 (스펙 § 11 요약)

| M | 범위 요약 | M1.2 결과로부터의 인풋 |
|---|---|---|
| **1.3** | 사이드바 3 섹션 (Pinned/Recent/Devices) + MountObserver + BreadcrumbBar + `⌘D` | FolderModel.selection 은 그대로 사용. Sidebar 진입 시 AppModel.navigate(to: entry) 가 history.push + FolderModel.load 트리거. |
| **1.4** | `cairn-preview` Rust + 이미지 썸네일 + MetaOnly + `Space` Quick Look + `⌘⇧.` | FolderModel.selection 의 첫 항목이 PreviewModel 로 push 되는 형태. `Space` 가 NSTableView keyDown 와 충돌하지 않게 chained-responder 처리 필요. |
| **1.5** | CairnTheme 토큰 + Glass Blue 팔레트 + NSVisualEffectView + 컨텍스트 메뉴 (Reveal / Copy Path / Trash) | Coordinator 에 `menu(for:row:)` delegate 추가 — 본 플랜에선 의도적으로 제외. |
| **1.6** | E2E 완주 + README + `create-dmg` + `v0.1.0-alpha` | development signing 으로 sandbox 실제 검증, M1.1 의 보류된 entitlements 거동 점검도 여기서. |

각 후속 마일스톤 플랜은 직전 M 완료 직후 작성 — 실행 러닝을 반영하기 위함. M1.2 의 예상 러닝: Coordinator 의 re-entrancy 가드, NSSortDescriptor key 문자열 매핑, byte/date 포맷 정렬 호환성, NSTableView ⏎ 처리.
