# Dual-Pane Compare & Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In dual-pane mode, let the user compare the two panes' folder contents and copy the delta (missing/changed files) either way, using the existing `TransferController` for actual file transfer.

**Architecture:** A pure-Swift `FolderCompare` function takes two `[FileEntry]` snapshots and returns a `CompareResult` bucketed into `onlyLeft / onlyRight / changed / same`. A `FolderCompareModel` (@Observable) drives the comparison asynchronously (shallow or recursive), exposes progress + cancel, and hands off to `TransferController` for the actual copy. UI is a sheet that splits the result into sections with checkboxes and two action buttons ("Copy to ← left" / "Copy to right →").

**Tech Stack:** Swift 5.9, SwiftUI, existing `FileSystemProvider`/`TransferController`, XCTest.

**Scope boundary:** Shallow compare by default. Recursive is a toggle. Comparison key is `name + size + mtime (±2s)` — no content hashing in v1 (hashing requires server-side hash that `cairn-ssh` doesn't yet offer). Delete-extra and two-way merge are not in scope; only copy forward.

---

## File Structure

**Create:**
- `apps/Sources/Services/FolderCompare.swift` — pure functions; takes two `[FileEntry]` lists + a comparison mode, returns `CompareResult`.
- `apps/Sources/ViewModels/FolderCompareModel.swift` — `@Observable` driver: async scan, cancellation, progress counters, and the "execute" action that enqueues transfers.
- `apps/Sources/Views/Compare/FolderCompareSheet.swift` — the SwiftUI sheet.
- `apps/Sources/Views/Compare/CompareRow.swift` — one row (checkbox + name + relative-size badge).
- `apps/CairnTests/FolderCompareTests.swift`
- `apps/CairnTests/FolderCompareModelTests.swift`

**Modify:**
- `apps/Sources/Views/PaneColumn.swift` or wherever the dual-pane toolbar lives — add a "Compare" button that opens the sheet with both panes' current folders.
- `apps/Sources/App/AppModel.swift` — hold the shared `FolderCompareModel` (or instantiate ad-hoc per open; executor's call).

---

## Task 1: CompareEntry + CompareResult types

**Files:**
- Create: `apps/Sources/Services/FolderCompare.swift`
- Test: `apps/CairnTests/FolderCompareTests.swift`

- [ ] **Step 1: Failing test**

```swift
// apps/CairnTests/FolderCompareTests.swift
import XCTest
@testable import Cairn

final class FolderCompareTests: XCTestCase {
    func test_result_isEmpty_whenBothSidesIdentical() {
        let left  = [entry(name: "a", size: 10, mtime: 100)]
        let right = [entry(name: "a", size: 10, mtime: 100)]
        let result = FolderCompare.compare(left: left, right: right, mode: .nameSizeMtime)
        XCTAssertTrue(result.onlyLeft.isEmpty)
        XCTAssertTrue(result.onlyRight.isEmpty)
        XCTAssertTrue(result.changed.isEmpty)
        XCTAssertEqual(result.same.map(\.name), ["a"])
    }

    private func entry(name: String, size: Int64, mtime: TimeInterval) -> CompareEntry {
        CompareEntry(name: name, size: size, mtime: Date(timeIntervalSince1970: mtime), isDirectory: false)
    }
}
```

- [ ] **Step 2: Verify fail**

Run: `make test 2>&1 | grep -E "FolderCompare|onlyLeft"`

- [ ] **Step 3: Implement types + trivial compare**

```swift
// apps/Sources/Services/FolderCompare.swift
import Foundation

struct CompareEntry: Equatable {
    let name: String
    let size: Int64
    let mtime: Date
    let isDirectory: Bool
}

enum CompareMode {
    case nameOnly
    case nameSize
    case nameSizeMtime
}

struct CompareResult: Equatable {
    var onlyLeft: [CompareEntry] = []
    var onlyRight: [CompareEntry] = []
    var changed: [CompareEntry] = []
    var same: [CompareEntry] = []
}

enum FolderCompare {
    /// Pure diff over two flat entry lists. Comparison keys:
    ///   - nameOnly: presence alone
    ///   - nameSize: size equality
    ///   - nameSizeMtime: size AND mtime equality within ±2s
    static func compare(left: [CompareEntry],
                        right: [CompareEntry],
                        mode: CompareMode) -> CompareResult {
        var result = CompareResult()
        let rightByName = Dictionary(uniqueKeysWithValues: right.map { ($0.name, $0) })
        var seen = Set<String>()

        for l in left {
            if let r = rightByName[l.name] {
                seen.insert(l.name)
                if isEqual(l, r, mode: mode) {
                    result.same.append(l)
                } else {
                    result.changed.append(l)
                }
            } else {
                result.onlyLeft.append(l)
            }
        }
        for r in right where !seen.contains(r.name) {
            result.onlyRight.append(r)
        }
        return result
    }

    private static func isEqual(_ a: CompareEntry, _ b: CompareEntry, mode: CompareMode) -> Bool {
        switch mode {
        case .nameOnly: return true
        case .nameSize: return a.size == b.size
        case .nameSizeMtime:
            return a.size == b.size && abs(a.mtime.timeIntervalSince(b.mtime)) <= 2
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/FolderCompare.swift apps/CairnTests/FolderCompareTests.swift
git commit -m "feat(compare): CompareResult + pure flat diff"
```

---

## Task 2: onlyLeft / onlyRight / changed behavior

**Files:**
- Test: `apps/CairnTests/FolderCompareTests.swift`

- [ ] **Step 1: Failing tests for all three buckets**

```swift
func test_onlyLeft_whenNameMissingOnRight() {
    let result = FolderCompare.compare(
        left: [entry(name: "a", size: 1, mtime: 0), entry(name: "b", size: 1, mtime: 0)],
        right: [entry(name: "a", size: 1, mtime: 0)],
        mode: .nameSizeMtime
    )
    XCTAssertEqual(result.onlyLeft.map(\.name), ["b"])
    XCTAssertTrue(result.onlyRight.isEmpty)
}

func test_onlyRight_whenNameMissingOnLeft() {
    let result = FolderCompare.compare(
        left:  [entry(name: "a", size: 1, mtime: 0)],
        right: [entry(name: "a", size: 1, mtime: 0), entry(name: "b", size: 1, mtime: 0)],
        mode: .nameSizeMtime
    )
    XCTAssertEqual(result.onlyRight.map(\.name), ["b"])
}

func test_changed_whenSizeDiffers() {
    let result = FolderCompare.compare(
        left:  [entry(name: "a", size: 1, mtime: 0)],
        right: [entry(name: "a", size: 2, mtime: 0)],
        mode: .nameSizeMtime
    )
    XCTAssertEqual(result.changed.map(\.name), ["a"])
}

func test_changed_whenMtimeDiffersBeyondTolerance() {
    let result = FolderCompare.compare(
        left:  [entry(name: "a", size: 1, mtime: 0)],
        right: [entry(name: "a", size: 1, mtime: 5)],
        mode: .nameSizeMtime
    )
    XCTAssertEqual(result.changed.map(\.name), ["a"])
}

func test_nameOnlyMode_treatsAllMatchesAsSame() {
    let result = FolderCompare.compare(
        left:  [entry(name: "a", size: 1, mtime: 0)],
        right: [entry(name: "a", size: 999, mtime: 999)],
        mode: .nameOnly
    )
    XCTAssertEqual(result.same.map(\.name), ["a"])
    XCTAssertTrue(result.changed.isEmpty)
}
```

- [ ] **Step 2: Run tests — they should pass from Task 1's implementation**

If any fail, fix the compare function (most likely edge case around dictionary lookup or mtime tolerance sign).

- [ ] **Step 3: Commit**

```bash
git commit -am "test(compare): cover all four buckets + mode variations"
```

---

## Task 3: Recursive compare (directory descent)

**Files:**
- Modify: `apps/Sources/Services/FolderCompare.swift`
- Modify: `apps/CairnTests/FolderCompareTests.swift`

- [ ] **Step 1: Failing test**

```swift
func test_recursiveCompare_walksSubdirectoriesAndReportsRelativePaths() async throws {
    // Build a fixture: left has foo/a, foo/b; right has foo/a
    let left = InMemoryProvider(tree: [
        "/root": ["foo"],
        "/root/foo": ["a", "b"]
    ])
    let right = InMemoryProvider(tree: [
        "/root": ["foo"],
        "/root/foo": ["a"]
    ])
    let result = try await FolderCompare.compareRecursive(
        leftRoot: "/root", leftProvider: left,
        rightRoot: "/root", rightProvider: right,
        mode: .nameSizeMtime,
        cancel: CancelToken()
    )
    XCTAssertEqual(result.onlyLeft.map(\.name), ["foo/b"])
}
```

Note: `InMemoryProvider` is a minimal `FileSystemProvider` double — reuse the one from the remote-edit plan or create a trimmer version inline.

- [ ] **Step 2: Verify fail**

- [ ] **Step 3: Implement recursive walk**

```swift
extension FolderCompare {
    /// Walk both trees BFS and emit a single flattened CompareResult where
    /// `name` is the path *relative* to the root on each side. Directories
    /// themselves aren't reported — only their children — so the executor
    /// can simply `cp --preserve` the individual files.
    static func compareRecursive(leftRoot: String,
                                 leftProvider: FileSystemProvider,
                                 rightRoot: String,
                                 rightProvider: FileSystemProvider,
                                 mode: CompareMode,
                                 cancel: CancelToken,
                                 onProgress: (Int) -> Void = { _ in }) async throws -> CompareResult {
        var result = CompareResult()
        var stack: [(String, String)] = [("", "")]  // relative subpath on each side
        while let (leftSub, rightSub) = stack.popLast() {
            if cancel.isCancelled { return result }
            let leftPath = FSPath(provider: leftProvider.identifier, path: leftRoot + (leftSub.isEmpty ? "" : "/" + leftSub))
            let rightPath = FSPath(provider: rightProvider.identifier, path: rightRoot + (rightSub.isEmpty ? "" : "/" + rightSub))

            async let leftList = leftProvider.list(leftPath)
            async let rightList = rightProvider.list(rightPath)
            let (lEntries, rEntries) = try await (leftList, rightList)

            let lCmp = lEntries.map { compareEntry(from: $0, relativeParent: leftSub) }
            let rCmp = rEntries.map { compareEntry(from: $0, relativeParent: rightSub) }
            let sub = compare(left: lCmp, right: rCmp, mode: mode)
            result.onlyLeft.append(contentsOf: sub.onlyLeft)
            result.onlyRight.append(contentsOf: sub.onlyRight)
            result.changed.append(contentsOf: sub.changed)
            onProgress(result.onlyLeft.count + result.onlyRight.count + result.changed.count)

            // Descend into dirs present on both sides.
            for l in lEntries where l.kind == .Directory {
                if let r = rEntries.first(where: { $0.name == l.name && $0.kind == .Directory }) {
                    let nextSub = leftSub.isEmpty ? l.name : leftSub + "/" + l.name
                    stack.append((nextSub, nextSub))
                    _ = r
                }
            }
        }
        return result
    }

    private static func compareEntry(from entry: FileEntry, relativeParent: String) -> CompareEntry {
        let relName = relativeParent.isEmpty ? entry.name : relativeParent + "/" + entry.name
        return CompareEntry(
            name: relName,
            size: entry.size,
            mtime: entry.mtime ?? .distantPast,
            isDirectory: entry.kind == .Directory
        )
    }
}
```

- [ ] **Step 4: Run test, expect pass**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(compare): recursive compare with relative-path reporting"
```

---

## Task 4: FolderCompareModel — async driver with cancel

**Files:**
- Create: `apps/Sources/ViewModels/FolderCompareModel.swift`
- Test: `apps/CairnTests/FolderCompareModelTests.swift`

- [ ] **Step 1: Failing test**

```swift
@MainActor
final class FolderCompareModelTests: XCTestCase {
    func test_run_populatesResultAndFlipsPhase() async throws {
        let provider = InMemoryProvider(tree: [
            "/L": ["a", "b"],
            "/R": ["a"]
        ])
        let model = FolderCompareModel()
        await model.run(
            leftRoot: FSPath(provider: .local, path: "/L"),
            rightRoot: FSPath(provider: .local, path: "/R"),
            leftProvider: provider, rightProvider: provider,
            mode: .nameSizeMtime, recursive: false
        )
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.result.onlyLeft.map(\.name), ["b"])
    }
}
```

- [ ] **Step 2: Verify fail**

- [ ] **Step 3: Implement model**

```swift
// apps/Sources/ViewModels/FolderCompareModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class FolderCompareModel {
    enum Phase: Equatable { case idle, running, done, failed(String), cancelled }

    private(set) var phase: Phase = .idle
    private(set) var result: CompareResult = CompareResult()
    private(set) var scannedCount: Int = 0

    private var task: Task<Void, Never>?
    private var cancel: CancelToken?

    func run(leftRoot: FSPath, rightRoot: FSPath,
             leftProvider: FileSystemProvider, rightProvider: FileSystemProvider,
             mode: CompareMode, recursive: Bool) async {
        cancelRunning()
        phase = .running
        result = CompareResult()
        scannedCount = 0
        let token = CancelToken()
        self.cancel = token
        do {
            let r: CompareResult
            if recursive {
                r = try await FolderCompare.compareRecursive(
                    leftRoot: leftRoot.path, leftProvider: leftProvider,
                    rightRoot: rightRoot.path, rightProvider: rightProvider,
                    mode: mode, cancel: token,
                    onProgress: { [weak self] n in Task { @MainActor in self?.scannedCount = n } }
                )
            } else {
                async let l = leftProvider.list(leftRoot)
                async let rr = rightProvider.list(rightRoot)
                let (lE, rE) = try await (l, rr)
                let lCmp = lE.map { CompareEntry(name: $0.name, size: $0.size, mtime: $0.mtime ?? .distantPast, isDirectory: $0.kind == .Directory) }
                let rCmp = rE.map { CompareEntry(name: $0.name, size: $0.size, mtime: $0.mtime ?? .distantPast, isDirectory: $0.kind == .Directory) }
                r = FolderCompare.compare(left: lCmp, right: rCmp, mode: mode)
            }
            result = r
            phase = .done
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func cancelRunning() {
        cancel?.cancel()
        task?.cancel()
        phase = .cancelled
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(compare): @Observable model drives async compare"
```

---

## Task 5: Execute — copy delta via TransferController

**Files:**
- Modify: `apps/Sources/ViewModels/FolderCompareModel.swift`
- Test: `apps/CairnTests/FolderCompareModelTests.swift`

- [ ] **Step 1: Failing test**

```swift
func test_applySync_enqueuesTransfersForSelectedEntries() async {
    let transfers = TransferController()
    let model = FolderCompareModel()
    // Preload a fake result as if we already ran.
    model.result.onlyLeft = [CompareEntry(name: "a", size: 1, mtime: Date(), isDirectory: false)]
    model.applySync(
        direction: .leftToRight,
        selected: Set(["a"]),
        leftRoot: FSPath(provider: .local, path: "/L"),
        rightRoot: FSPath(provider: .local, path: "/R"),
        transfers: transfers
    )
    XCTAssertEqual(transfers.pendingOrActiveCount, 1)
}
```

`pendingOrActiveCount` is a test-visible computed var on `TransferController` (add it if missing).

- [ ] **Step 2: Verify fail**

- [ ] **Step 3: Implement apply**

```swift
enum CompareDirection { case leftToRight, rightToLeft }

func applySync(direction: CompareDirection,
               selected: Set<String>,
               leftRoot: FSPath,
               rightRoot: FSPath,
               transfers: TransferController) {
    // Decide the relevant buckets per direction.
    let pool: [CompareEntry]
    let (srcRoot, dstRoot): (FSPath, FSPath)
    switch direction {
    case .leftToRight:
        pool = result.onlyLeft + result.changed
        (srcRoot, dstRoot) = (leftRoot, rightRoot)
    case .rightToLeft:
        pool = result.onlyRight + result.changed
        (srcRoot, dstRoot) = (rightRoot, leftRoot)
    }
    for entry in pool where selected.contains(entry.name) {
        let src = FSPath(provider: srcRoot.provider, path: srcRoot.path + "/" + entry.name)
        let dst = FSPath(provider: dstRoot.provider, path: dstRoot.path + "/" + entry.name)
        transfers.enqueue(source: src, destination: dst, sizeHint: entry.size, displayName: entry.name)
    }
}
```

(The exact `transfers.enqueue` signature may differ — match what `TransferController.swift:24` expects.)

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(compare): apply selected delta via TransferController"
```

---

## Task 6: FolderCompareSheet — top-level UI

**Files:**
- Create: `apps/Sources/Views/Compare/FolderCompareSheet.swift`
- Create: `apps/Sources/Views/Compare/CompareRow.swift`

- [ ] **Step 1: CompareRow**

```swift
import SwiftUI

struct CompareRow: View {
    let entry: CompareEntry
    @Binding var isSelected: Bool
    let bucketColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isSelected).labelsHidden()
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .foregroundStyle(bucketColor)
            Text(entry.name).font(.system(size: 12))
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }
}
```

- [ ] **Step 2: FolderCompareSheet**

```swift
import SwiftUI

struct FolderCompareSheet: View {
    @Bindable var model: FolderCompareModel
    let transfers: TransferController
    let leftRoot: FSPath
    let rightRoot: FSPath
    let leftProvider: FileSystemProvider
    let rightProvider: FileSystemProvider
    let onDismiss: () -> Void

    @State private var mode: CompareMode = .nameSizeMtime
    @State private var recursive = false
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.phase == .running {
                ProgressView("Scanning… (\(model.scannedCount))")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                results
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 480)
        .task { await runScan() }
    }

    private var header: some View {
        HStack {
            Text("Compare").font(.title3.bold())
            Spacer()
            Picker("Mode", selection: $mode) {
                Text("Name only").tag(CompareMode.nameOnly)
                Text("+ size").tag(CompareMode.nameSize)
                Text("+ size + mtime").tag(CompareMode.nameSizeMtime)
            }.pickerStyle(.segmented).frame(width: 320)
            Toggle("Recursive", isOn: $recursive)
            Button("Rescan") { Task { await runScan() } }
        }.padding(12)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                section(title: "Only on left",  entries: model.result.onlyLeft,  color: .blue)
                section(title: "Only on right", entries: model.result.onlyRight, color: .green)
                section(title: "Changed",       entries: model.result.changed,   color: .orange)
            }.padding(.horizontal, 10)
        }
    }

    private func section(title: String, entries: [CompareEntry], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(title) (\(entries.count))").font(.headline).foregroundStyle(color)
                Spacer()
                if !entries.isEmpty {
                    Button("Select all") { selected.formUnion(entries.map(\.name)) }
                    Button("Clear") { selected.subtract(entries.map(\.name)) }
                }
            }.padding(.vertical, 6)
            ForEach(entries, id: \.name) { e in
                CompareRow(entry: e, isSelected: Binding(
                    get: { selected.contains(e.name) },
                    set: { on in if on { selected.insert(e.name) } else { selected.remove(e.name) } }
                ), bucketColor: color)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Close", action: onDismiss).keyboardShortcut(.cancelAction)
            Spacer()
            Button("Copy ← to left") { apply(.rightToLeft) }
            Button("Copy → to right") { apply(.leftToRight) }
                .keyboardShortcut(.defaultAction)
        }.padding(12)
    }

    private func runScan() async {
        await model.run(leftRoot: leftRoot, rightRoot: rightRoot,
                        leftProvider: leftProvider, rightProvider: rightProvider,
                        mode: mode, recursive: recursive)
    }

    private func apply(_ direction: CompareDirection) {
        model.applySync(direction: direction, selected: selected,
                        leftRoot: leftRoot, rightRoot: rightRoot, transfers: transfers)
        onDismiss()
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
git add apps/Sources/Views/Compare
git commit -m "feat(compare): SwiftUI sheet + per-bucket selection"
```

---

## Task 7: Dual-pane toolbar entry

**Files:**
- Modify: `apps/Sources/Views/PaneColumn.swift` (or the toolbar host — grep for the split-view toggle icon).
- Modify: `apps/Sources/ContentView.swift` — holds the sheet presentation state if toolbar lives there.

- [ ] **Step 1: Add toolbar button**

Find where the existing dual-pane split toggle renders (the icon top-left of the screenshots the user has shown earlier). Add adjacent:

```swift
Button {
    if let (l, r) = dualPane.bothFolders() {  // helper returning (leftFSPath, rightFSPath) or nil
        compareSheet = CompareSheetConfig(leftRoot: l.0, rightRoot: r.0,
                                          leftProvider: l.1, rightProvider: r.1)
    }
} label: { Image(systemName: "rectangle.split.2x1.slash") }
.disabled(!dualPane.isSplit)
.help("Compare left and right folders")
```

Add the helper on `WindowDualPaneModel`:

```swift
func bothFolders() -> (left: (FSPath, FileSystemProvider), right: (FSPath, FileSystemProvider))? {
    guard isSplit,
          let l = leftPane.activeTab, let r = rightPane.activeTab,
          let lp = l.currentPath, let rp = r.currentPath else { return nil }
    return ((lp, l.provider), (rp, r.provider))
}
```

And render the sheet in the same view:

```swift
.sheet(item: $compareSheet) { cfg in
    FolderCompareSheet(
        model: compareModel,
        transfers: app.transfers,
        leftRoot: cfg.leftRoot, rightRoot: cfg.rightRoot,
        leftProvider: cfg.leftProvider, rightProvider: cfg.rightProvider,
        onDismiss: { compareSheet = nil }
    )
}
```

- [ ] **Step 2: Build + visual smoke**

Run: `make run`, split to dual pane, click the new button, verify the sheet scans.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(compare): toolbar button opens compare sheet in dual-pane mode"
```

---

## Task 8: Progress & cancel during large recursive scans

**Files:**
- Modify: `apps/Sources/Views/Compare/FolderCompareSheet.swift`
- Modify: `apps/Sources/ViewModels/FolderCompareModel.swift`

- [ ] **Step 1: Cancel button in the ProgressView branch**

```swift
VStack(spacing: 8) {
    ProgressView("Scanning… (\(model.scannedCount))")
    Button("Cancel") { model.cancelRunning() }
}
```

- [ ] **Step 2: Handle .cancelled phase**

In the sheet body's switch, render a dismissible cancelled state:

```swift
if case .cancelled = model.phase {
    Text("Scan cancelled").foregroundStyle(.secondary)
    Button("Retry") { Task { await runScan() } }
}
```

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(compare): cancel button for long recursive scans"
```

---

## Task 9: Remote ↔ local sanity test

**Files:**
- Create: `apps/CairnTests/FolderCompareIntegrationTests.swift`

- [ ] **Step 1: Test guarded on CAIRN_IT_SSH_HOST**

```swift
func test_compareLocalToRemote_detectsOnlyRightEntries() async throws {
    guard let host = ProcessInfo.processInfo.environment["CAIRN_IT_SSH_HOST"] else {
        throw XCTSkip("no live ssh")
    }
    // Upload a fixture dir, scan local vs remote, assert onlyRight empty, same dominated.
}
```

- [ ] **Step 2: Commit**

```bash
git commit -am "test(compare): gated local↔remote integration"
```

---

## Self-Review

**Spec coverage**
- ✅ Compare two sides → Task 1, Task 3.
- ✅ Show missing/changed → Task 6 (sheet with three buckets).
- ✅ Selective copy → Task 5 + footer buttons.
- ✅ Dual-pane integration → Task 7.
- ✅ Hooks existing TransferController → Task 5.

**Placeholder scan**
- `transfers.enqueue(...)` signature flagged as "match existing" — the executor must read `TransferController.swift:24`.
- `WindowDualPaneModel.bothFolders()` helper added in Task 7 — reviewer confirms the model has access to both panes.

**Type consistency**
- `CompareEntry`, `CompareResult`, `CompareMode`, `CompareDirection`, `FolderCompareModel.Phase` referenced uniformly across tasks.
- `FolderCompareModel.run` and `.applySync` signatures stable.
