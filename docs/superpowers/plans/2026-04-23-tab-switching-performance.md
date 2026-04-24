# Tab Switching Performance Implementation Plan

> **For Codex executor:** Each task is self-contained with exact file paths and code. Follow task order. Build/test after each task before moving on. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tab switching feel instant with 4+ tabs open, including at least one SSH remote tab — eliminate the "밀리는" (pushing/lagging) animation and reduce wasted work in background tabs.

**Architecture:** Three independent fixes that compound — (1) pause per-tab FolderWatcher when the tab goes inactive so background tabs don't fire main-thread debounce timers; (2) collapse the duplicate `folder.load` that currently fires twice on every tab switch (once from `activeTabID` onChange, once from `currentPath` onChange); (3) cache the last listing per Tab so switching back to a previously-visited tab shows content instantly, then refreshes in the background.

**Tech Stack:** Swift / SwiftUI / AppKit, `DispatchSource` kqueue watcher, `FolderModel` (the observed entries container), `Tab`, `PaneColumn`.

**Reference files (read first):**
- `apps/Sources/App/Tab.swift` — per-tab state (lines 42-47 folderWatcher; 237-312 rebuild; 257-272 watcher lifecycle).
- `apps/Sources/Services/FolderWatcher.swift` — the kqueue wrapper (all 62 lines).
- `apps/Sources/App/WindowSceneModel.swift` — tabs array + activeTabID (lines 12-13).
- `apps/Sources/Views/PaneColumn.swift:55-77` — the duplicate `onChange` block.
- `apps/Sources/Views/FolderModel.swift` (or wherever `FolderModel` lives — see "Preparation" below).
- `apps/Sources/Views/Tabs/TabBarView.swift` — tab chip layout (no scroll).

**Preparation:** Before starting, locate `FolderModel`:
```bash
grep -rn "final class FolderModel\|class FolderModel" apps/Sources --include="*.swift"
```
Record the path; Tasks 1 and 3 reference it.

---

## File Structure

- **Modify:** `apps/Sources/Services/FolderWatcher.swift` — add `pause()` / `resume()` methods.
- **Modify:** `apps/Sources/App/Tab.swift` — add `setActive(_:)` that pauses/resumes watcher, and a per-tab last-listing snapshot that survives the folder reload.
- **Modify:** `apps/Sources/App/WindowSceneModel.swift` — call `setActive(_:)` on tabs when `activeTabID` changes.
- **Modify:** `apps/Sources/Views/PaneColumn.swift` — delete the duplicate `folder.load` in the `activeTabID` onChange; keep only the `currentPath` onChange.
- **Modify:** `apps/Sources/Views/Tabs/TabBarView.swift` — wrap chips in a horizontal `ScrollView`.
- **Test:** `apps/CairnTests/FolderWatcherLifecycleTests.swift` — pause/resume unit test.
- **Test:** `apps/CairnTests/TabActivationTests.swift` — assert watcher state tracks active flag.

---

## Task 1: Add pause/resume to FolderWatcher

**Files:**
- Modify: `apps/Sources/Services/FolderWatcher.swift`
- Test: `apps/CairnTests/FolderWatcherLifecycleTests.swift` (create)

The DispatchSource file system object source supports `suspend()` / `resume()`. Calling `suspend()` stops event delivery (but retains the fd); `resume()` starts delivery again. This is cheaper than tearing down + reopening the watcher on every tab switch.

- [ ] **Step 1: Write the failing test**

Create `apps/CairnTests/FolderWatcherLifecycleTests.swift`:

```swift
import XCTest
@testable import Cairn

final class FolderWatcherLifecycleTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func test_pause_suppressesEventsUntilResume() throws {
        let fireExpectation = XCTestExpectation(description: "event fired")
        fireExpectation.isInverted = true  // should NOT fire while paused
        let resumedExpectation = XCTestExpectation(description: "event after resume")

        var pauseActive = true
        let watcher = FolderWatcher(root: dir) {
            if pauseActive {
                fireExpectation.fulfill()
            } else {
                resumedExpectation.fulfill()
            }
        }
        XCTAssertNotNil(watcher)
        watcher!.pause()

        // Mutate dir while paused
        let f = dir.appendingPathComponent("a.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        wait(for: [fireExpectation], timeout: 0.5)

        pauseActive = false
        watcher!.resume()
        // Mutate again to trigger a fresh event
        let f2 = dir.appendingPathComponent("b.txt")
        try "y".write(to: f2, atomically: true, encoding: .utf8)
        wait(for: [resumedExpectation], timeout: 1.0)
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:
```bash
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn -only-testing:CairnTests/FolderWatcherLifecycleTests 2>&1 | tail -20
```
Expected: compile error — `pause()` and `resume()` are not defined on `FolderWatcher`.

- [ ] **Step 3: Add pause/resume methods**

In `apps/Sources/Services/FolderWatcher.swift`, append these methods inside the `FolderWatcher` class (before the closing brace):

```swift
    /// Stop delivering events (kqueue stays open, fd stays valid). Idempotent.
    /// Used when the owning tab becomes a background tab — there's no point
    /// reloading a folder the user isn't looking at.
    func pause() {
        guard !isSuspended else { return }
        source?.suspend()
        isSuspended = true
        debounceWork?.cancel()
    }

    /// Resume event delivery. Idempotent. When a tab becomes active again,
    /// fires `onChange` once immediately so any changes that happened while
    /// paused trigger a refresh.
    func resume() {
        guard isSuspended else { return }
        source?.resume()
        isSuspended = false
        onChange()
    }
```

Also add the state flag inside the class (near the other stored properties at line 25):

```swift
    private var isSuspended: Bool = false
```

- [ ] **Step 4: Run tests and verify pass**

Run:
```bash
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn -only-testing:CairnTests/FolderWatcherLifecycleTests 2>&1 | tail -20
```
Expected: test passes.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/FolderWatcher.swift apps/CairnTests/FolderWatcherLifecycleTests.swift
git commit -m "feat(watcher): add pause/resume to FolderWatcher"
```

---

## Task 2: Tab active/inactive lifecycle hook

**Files:**
- Modify: `apps/Sources/App/Tab.swift`
- Test: `apps/CairnTests/TabActivationTests.swift` (create)

Add a `setActive(_:)` method on `Tab` that forwards to the watcher. Keep index / git services running because they're not event-driven (they ran once when the tab opened). Only the watcher debounce-fires repeatedly and is worth pausing.

- [ ] **Step 1: Write the failing test**

Create `apps/CairnTests/TabActivationTests.swift`:

```swift
import XCTest
@testable import Cairn

@MainActor
final class TabActivationTests: XCTestCase {
    func test_setActive_flagTogglesIsActive() {
        let engine = try! CairnEngine()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BookmarkStore(storageDirectory: tmp)
        let tab = Tab(engine: engine, bookmarks: store, initialURL: tmp)

        XCTAssertTrue(tab.isActive, "new tab should start active")
        tab.setActive(false)
        XCTAssertFalse(tab.isActive)
        tab.setActive(true)
        XCTAssertTrue(tab.isActive)
    }
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:
```bash
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn -only-testing:CairnTests/TabActivationTests 2>&1 | tail -20
```
Expected: compile error — `isActive` and `setActive` not defined.

- [ ] **Step 3: Add the property and method**

In `apps/Sources/App/Tab.swift`:

(a) Add the property near the other stored vars (around line 47, after `private var folderWatcher: FolderWatcher?`):

```swift
    /// Whether the tab is currently the active tab in its window. When false,
    /// the folderWatcher is paused so background tabs don't fire reload tasks
    /// on every external FS change. Index + git services keep running because
    /// they're one-shot (opened once per navigation, not event-driven).
    private(set) var isActive: Bool = true
```

(b) Add the method just below `rebuildServices(for:)` (around line 313, inside the class):

```swift
    // MARK: - Tab activation

    /// Called by WindowSceneModel when the active tab changes. Pauses the
    /// folder watcher on deactivation; resumes on re-activation (which also
    /// fires one reload so any background FS changes are picked up).
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            folderWatcher?.resume()
        } else {
            folderWatcher?.pause()
        }
    }
```

- [ ] **Step 4: Run test and verify pass**

Run:
```bash
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn -only-testing:CairnTests/TabActivationTests 2>&1 | tail -20
```
Expected: test passes.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/App/Tab.swift apps/CairnTests/TabActivationTests.swift
git commit -m "feat(tab): add setActive to pause folder watcher on background tabs"
```

---

## Task 3: Wire WindowSceneModel to broadcast active flag

**Files:**
- Modify: `apps/Sources/App/WindowSceneModel.swift`

Whenever `activeTabID` changes, call `setActive(true)` on the new active tab and `setActive(false)` on the rest. Do the same when a new tab is appended (new tab is active, others go inactive).

- [ ] **Step 1: Add a helper that reconciles active flags**

In `apps/Sources/App/WindowSceneModel.swift`, add a private helper inside the class (insert before the closing brace at line 108):

```swift
    /// Drive `Tab.setActive(_:)` across all tabs so only the active tab's
    /// FSEvent watcher runs. Called after any mutation of `tabs` or
    /// `activeTabID`.
    private func reconcileActiveFlags() {
        for t in tabs {
            t.setActive(t.id == activeTabID)
        }
    }
```

- [ ] **Step 2: Convert `activeTabID` to a didSet-observing property**

Replace the `var activeTabID: Tab.ID?` declaration (line 13) with:

```swift
    var activeTabID: Tab.ID? {
        didSet { reconcileActiveFlags() }
    }
```

**Risk note:** `WindowSceneModel` is `@Observable`. Adding a `didSet` to a stored property under the Observation macro has worked in practice (the macro's expansion wraps the accessors and the explicit didSet still fires on mutation), but verify with a quick print in the didSet the first time you run the app. If you find `didSet` isn't firing — fall back to explicit `reconcileActiveFlags()` calls from every mutation site (Step 3) and drop the didSet. The explicit-calls fallback alone is sufficient to keep the feature correct.

- [ ] **Step 3: Call reconciler from tab-list mutations**

In the same file, add `reconcileActiveFlags()` at the end of these methods:

- `newTab(cloningActive:)` — after `activeTabID = t.id` (line 50).
- `newRemoteTab(initialPath:provider:)` — after `activeTabID = t.id` (line 57).
- `newEstablishingTab(alias:)` — after `activeTabID = t.id` (line 71), BEFORE the `return t`.
- `closeTab(_:)` — after `activeTabID = tabs.last?.id` (line 82).

Example for `newTab`:

```swift
    func newTab(cloningActive: Bool = true) {
        let url: URL
        if cloningActive, let current = activeTab?.currentFolder {
            url = current
        } else {
            url = FileManager.default.homeDirectoryForCurrentUser
        }
        let t = Tab(engine: engine, bookmarks: bookmarks, initialURL: url)
        tabs.append(t)
        activeTabID = t.id  // didSet fires reconcileActiveFlags
    }
```

Because `activeTabID` now has a `didSet`, setting it from the other methods already triggers reconciliation. **Only `newEstablishingTab` and `closeTab` need an explicit trailing call** in edge cases where the id might equal the previous one. To keep the plan simple and deterministic, add an explicit `reconcileActiveFlags()` call at the tail of all four methods.

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Debug build -quiet
```
Expected: build succeeds.

- [ ] **Step 5: Run all tests**

Run:
```bash
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn 2>&1 | tail -30
```
Expected: all tests pass (including the two new ones from Tasks 1-2 and existing `WindowSceneModelTests`).

- [ ] **Step 6: Commit**

```bash
git add apps/Sources/App/WindowSceneModel.swift
git commit -m "feat(scene): reconcile tab active flags on tab list / activeTabID change"
```

---

## Task 4: Remove duplicate folder.load on tab switch

**Files:**
- Modify: `apps/Sources/Views/PaneColumn.swift`

`PaneColumn` has two `onChange` handlers that both call `folder.load` when the active tab changes:

1. `onChange(of: tab?.currentPath)` at line 60 — fires because the computed `tab` changes.
2. `onChange(of: scene.activeTabID)` at line 68 — fires explicitly.

For a local tab this means two sequential `folder.load` calls (mostly dedupable by FolderModel's own equality check). For an SSH tab each load is a full SFTP LIST round trip — **two round trips per switch**. Kill the redundant one.

- [ ] **Step 1: Remove the second `folder.load` in the `activeTabID` onChange**

In `apps/Sources/Views/PaneColumn.swift`, replace the `onChange(of: scene.activeTabID)` block (lines 68-72):

```swift
            .onChange(of: scene.activeTabID) { _, _ in
                onFocus()
                guard let tab, let path = tab.currentPath else { return }
                Task { await tab.folder.load(path, via: tab.provider) }
            }
```

with:

```swift
            .onChange(of: scene.activeTabID) { _, _ in
                onFocus()
                // Do NOT call folder.load here — the `tab?.currentPath`
                // onChange above already fires when the active tab changes
                // (since `tab` is computed from `scene.activeTab`), and an
                // SSH tab's LIST is a full round trip. Duplicate load was
                // observed at tab-switch time producing a visible "밀림".
            }
```

- [ ] **Step 2: Build and verify no regressions**

Run:
```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Debug build -quiet
```

- [ ] **Step 3: Manual smoke test**

1. Open the app with 3+ tabs: Downloads, Home, and one SSH tab.
2. Click through the tabs rapidly.
3. Expected: each switch shows the listing within a few hundred ms; no noticeable pause as prior animation cascades.
4. Open Console.app and filter for "Cairn" — no errors.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/Views/PaneColumn.swift
git commit -m "fix(pane): drop duplicate folder.load in activeTabID onChange"
```

---

## Task 5: Skip needless listing reload on pure tab-focus swap

**Files:**
- Modify: `apps/Sources/Views/PaneColumn.swift`

**Pre-verified:** `FolderModel.load` (in `apps/Sources/ViewModels/FolderModel.swift:79-95`) already does an atomic swap — it does NOT clear `entries` at the start. It sets `state = .loading`, performs `provider.list`, then overwrites `entries` on success. So a tab switch that triggers another `load` keeps the old entries on screen during the in-flight request; no blank flash from the model itself.

However, when two tabs happen to point at the **same path** (e.g. two Home tabs, or two tabs opened via ⌘T that cloned the active folder), the switch fires `.onChange(of: tab?.currentPath)` with the same value and still kicks off a reload. For SSH that's a wasted LIST round trip; for local it's a cheap but noisy reload that flips `state` to `.loading` and back.

Also: `FSPath` is already `Hashable` (`apps/Sources/Services/FSPath.swift:20`), which implies `Equatable`. Good — no synthesis needed.

- [ ] **Step 1: Add a path-unchanged early return**

In `apps/Sources/Views/PaneColumn.swift`, replace the `onChange(of: tab?.currentPath)` block (lines 60-67):

```swift
            .onChange(of: tab?.currentPath) { _, new in
                guard let tab else { return }
                guard let path = new else { tab.folder.clear(); return }
                if case .local = path.provider {
                    app.lastFolder.save(URL(fileURLWithPath: path.path))
                }
                Task { await tab.folder.load(path, via: tab.provider) }
            }
```

with:

```swift
            .onChange(of: tab?.currentPath) { old, new in
                guard let tab else { return }
                guard let path = new else { tab.folder.clear(); return }
                if case .local = path.provider {
                    app.lastFolder.save(URL(fileURLWithPath: path.path))
                }
                // Pure tab-focus swap where the new tab's path matches the
                // old one and it already has entries visible: skip the
                // reload (SFTP LIST round trip on remote, wasted work on
                // local). The FolderWatcher on the active tab will push
                // any subsequent changes through normally.
                if let o = old, o == path, !tab.folder.entries.isEmpty {
                    return
                }
                Task { await tab.folder.load(path, via: tab.provider) }
            }
```

- [ ] **Step 2: Build and manual smoke test**

Run:
```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Debug build -quiet
```

Manual:
1. Open two tabs both on `~`, switch between them several times.
2. Expected: no spinner flash, no re-render jitter.
3. Open a remote tab, navigate to some folder, switch to local tab, switch back.
4. Expected: remote listing still visible instantly on return (FolderModel's atomic swap behavior + watcher-resume from Task 2).

- [ ] **Step 3: Commit**

```bash
git add apps/Sources/Views/PaneColumn.swift
git commit -m "perf(pane): skip folder.load when tab-switch path is unchanged"
```

---

## Task 6: Horizontal scroll for TabBarView

**Files:**
- Modify: `apps/Sources/Views/Tabs/TabBarView.swift`

With 4+ tabs, `HStack` + `Spacer()` squishes chips and may trigger repeated SwiftUI layout passes. Wrapping the chips in a `ScrollView(.horizontal)` fixes both the visual squish and the layout thrash.

- [ ] **Step 1: Wrap the HStack in a horizontal ScrollView**

Replace the entire `TabBarView.body` (lines 13-41) with:

```swift
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(scene.tabs) { tab in
                        TabChip(
                            label: tab.titleText,
                            isActive: tab.id == scene.activeTabID,
                            badge: tab.protocolBadge,
                            onActivate: { scene.activeTabID = tab.id },
                            onClose: { scene.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
            Button(action: { scene.newTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .padding(.vertical, 5)
        .frame(height: 38)
        .background(.thinMaterial)
    }
```

- [ ] **Step 2: Build and visual test**

Run:
```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Debug build -quiet
```

Open the app, create 8+ tabs, verify the tab bar scrolls horizontally and the "+" button stays pinned on the right.

- [ ] **Step 3: Commit**

```bash
git add apps/Sources/Views/Tabs/TabBarView.swift
git commit -m "fix(tabs): horizontal scroll so many tabs don't squish or relayout on switch"
```

---

## Final integration test

- [ ] **Step 1: Run full test suite**

```bash
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn 2>&1 | tail -30
```
Expected: all tests pass.

- [ ] **Step 2: Manual perf validation**

1. Launch the app.
2. Create tabs: Downloads, Home, workspace, and 2 SSH tabs to different hosts.
3. Cycle through all 5 tabs rapidly (⌘1 → ⌘2 → ⌘3 → ⌘4 → ⌘5).
4. Expected: each switch is visually instant; no loading spinner flash; CPU drops to idle within a second of stopping.
5. Use Activity Monitor to confirm Cairn's CPU drops to ~0% when idle with many tabs (previously background watchers kept it warm).

## Self-review checklist

- [ ] Task 1: `pause()` / `resume()` on FolderWatcher + test.
- [ ] Task 2: `Tab.setActive(_:)` + `isActive` flag + test.
- [ ] Task 3: `WindowSceneModel` reconciles on `activeTabID` didSet + 4 mutation methods.
- [ ] Task 4: PaneColumn duplicate `folder.load` removed.
- [ ] Task 5: path-unchanged early return in PaneColumn (FolderModel atomic-swap behavior pre-verified).
- [ ] Task 6: TabBar in horizontal ScrollView.
- [ ] All automated tests pass.
- [ ] Manual 5-tab cycle feels instant.

## Out of scope (track as follow-ups)

- **IndexService pause for background tabs.** Tantivy is already one-shot per navigation so the cost is low; no pause wiring needed right now.
- **Virtualized FileListView for huge listings.** Orthogonal perf issue; covered by existing NSTableView backing.
- **Per-tab memory pressure handling.** If users open 30+ tabs on large folders we may want to drop entries for tabs untouched for >5min; not addressed here.
