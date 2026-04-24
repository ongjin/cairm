# Codex Adversarial Review Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three blockers flagged by the Codex adversarial review of `origin/main~5..HEAD` — (1) silent remote overwrite in `pasteImageToSSH`, (2) globally-disabled preview inspector regression, (3) app-wide pane-focus NSEvent monitor that leaks across windows.

**Architecture:** Keep changes minimal and scoped to the three affected files. For (1) extract a pure async helper that takes a probe closure so the naming loop is unit-testable without SSH. For (2) restore `.inspector` + toolbar toggle verbatim from `origin/main~5`, then add a provider-aware placeholder inside `PreviewPaneView` so remote tabs get "preview unavailable" instead of a broken view. For (3) introduce a tiny `WindowAccessor` `NSViewRepresentable` so each `PaneColumn` captures its host `NSWindow`, then hard-gate the click-to-focus monitor on `event.window === hostWindow`.

**Tech Stack:** Swift 5, SwiftUI, AppKit (`NSEvent.addLocalMonitorForEvents`, `NSViewRepresentable`), `SshFileSystemProvider.stat`, XCTest.

**Review source:** Codex adversarial review job `review-mobaogg4-c5qlhy` (2026-04-23), branch diff vs `origin/main~5`.

---

## File Inventory

**Create**

- `apps/Sources/Services/RemoteNameResolver.swift` — pure async helper `uniqueRemotePath(base:ext:in:probe:)` that produces a non-colliding remote `FSPath` given an async existence probe. Extracted so it can be unit-tested without a real SFTP handle.
- `apps/CairnTests/RemoteNameResolverTests.swift` — XCTest unit tests for the probe loop.
- `apps/Sources/Views/WindowAccessor.swift` — tiny `NSViewRepresentable` that publishes its host `NSWindow` through a `@Binding`. Used by `PaneColumn` (and reusable by any future SwiftUI view needing window identity).

**Modify**

- `apps/Sources/Views/FileList/FileListCoordinator.swift` — replace timestamp-based name in `pasteImageToSSH` with a stat-probing unique-destination lookup; move naming inside the `Task` so it can `await provider.stat`.
- `apps/Sources/ContentView.swift` — restore `.inspector(isPresented: $showInspector)` modifier, restore the toolbar toggle button, flip default `showInspector` back to `true`. Tidy the now-stale comments.
- `apps/Sources/Views/Preview/PreviewPaneView.swift` — render a small "Preview not available for remote files" card when the focused path is `.ssh(...)`; local path rendering unchanged.
- `apps/Sources/Views/PaneColumn.swift` — add `@State private var hostWindow: NSWindow?`, install a `WindowAccessor` in `.background`, and gate the `leftMouseDown` monitor on `event.window === hostWindow`.

---

# Section A — Remote screenshot paste collision (high)

Current code at `apps/Sources/Views/FileList/FileListCoordinator.swift:1208-1237` builds `Untitled-<epochSec>.<ext>` and calls `uploadFromLocal` directly. `uploadFromLocal` truncates existing destinations, so two pastes in the same second (or a pre-existing file with that name) silently overwrite the older file with no undo.

Fix: probe remote existence via `provider.stat` before upload; on hit, step through Finder's `appendNumber` scheme (`Untitled.png` → `Untitled 2.png` → `Untitled 3.png`…).

## Task A1: Create `RemoteNameResolver` pure helper

**Files:**
- Create: `apps/Sources/Services/RemoteNameResolver.swift`

- [ ] **Step 1: Write the file**

```swift
// apps/Sources/Services/RemoteNameResolver.swift
import Foundation

/// Pure async helper that walks `Untitled` → `Untitled 2` → `Untitled 3` …
/// until `probe(candidate)` reports "not present". Split out of the
/// remote-paste path so the naming loop is unit-testable without an
/// actual SFTP handle — the clipboard/paste surface is already a known
/// data-loss hazard (screenshots overwrite silently) so the probe loop
/// gets its own tests.
///
/// `probe` returns `true` iff the candidate already exists on the remote.
/// Callers pass `{ path in (try? await provider.stat(path)) != nil }` in
/// production, and a synchronous fake in tests.
enum RemoteNameResolver {
    static func uniqueRemotePath(
        base: String,
        ext: String,
        in dir: FSPath,
        probe: (FSPath) async -> Bool
    ) async -> FSPath {
        let first = dir.appending(ext.isEmpty ? base : "\(base).\(ext)")
        if await probe(first) == false { return first }
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appending(name)
            if await probe(candidate) == false { return candidate }
            n += 1
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Cairn -destination 'platform=macOS' -quiet build 2>&1 | tail -20`
Expected: build succeeds (no references yet — just compilation of the new file).

## Task A2: Write tests for `RemoteNameResolver`

**Files:**
- Create: `apps/CairnTests/RemoteNameResolverTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// apps/CairnTests/RemoteNameResolverTests.swift
import XCTest
@testable import Cairn

final class RemoteNameResolverTests: XCTestCase {
    private let dir = FSPath(provider: .local, path: "/tmp/fake")

    func test_noCollision_returnsBaseName() async {
        let existing: Set<String> = []
        let result = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled.png")
    }

    func test_oneCollision_appendsTwo() async {
        let existing: Set<String> = ["/tmp/fake/Untitled.png"]
        let result = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled 2.png")
    }

    func test_multipleCollisions_walksUntilFree() async {
        let existing: Set<String> = [
            "/tmp/fake/Untitled.png",
            "/tmp/fake/Untitled 2.png",
            "/tmp/fake/Untitled 3.png",
        ]
        let result = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled 4.png")
    }

    func test_emptyExtension_omitsDot() async {
        let result = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "", in: dir,
            probe: { _ in false }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled")
    }
}
```

- [ ] **Step 2: Run the tests and verify they pass**

Run: `xcodebuild test -scheme Cairn -destination 'platform=macOS' -only-testing:CairnTests/RemoteNameResolverTests 2>&1 | tail -30`
Expected: all four tests pass.

- [ ] **Step 3: Commit**

```bash
git add apps/Sources/Services/RemoteNameResolver.swift \
        apps/CairnTests/RemoteNameResolverTests.swift
git commit -m "feat(ssh): add RemoteNameResolver for collision-free remote names"
```

## Task A3: Wire `RemoteNameResolver` into `pasteImageToSSH`

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift:1208-1237`

- [ ] **Step 1: Replace the method body**

Current method (for reference):

```swift
private func pasteImageToSSH(data: Data, ext: String, into target: FSPath) {
    let filename = "Untitled-\(Int(Date().timeIntervalSince1970)).\(ext)"
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cairn-paste-\(UUID().uuidString).\(ext)")
    do {
        try data.write(to: tmpURL, options: .atomic)
    } catch {
        NSSound.beep()
        return
    }
    let dstPath = target.appending(filename)
    let size = Int64(data.count)
    Task { @MainActor [weak self] in
        guard let self else { return }
        self.transfers.enqueue(source: FSPath(provider: .local, path: tmpURL.path),
                               destination: dstPath,
                               sizeHint: size) { [weak self] job, progress in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            try await self.provider.uploadFromLocal(tmpURL, to: dstPath,
                                                    progress: progress,
                                                    cancel: job.cancel)
        }
    }
}
```

Replace with:

```swift
private func pasteImageToSSH(data: Data, ext: String, into target: FSPath) {
    // Stage clipboard bytes in a local temp file so the existing upload
    // pipeline can ship them. Remote destination is picked by probing
    // SFTP stat in a Finder-style "Untitled" → "Untitled 2" loop —
    // SFTP upload truncates existing targets, so we MUST guarantee a
    // non-existing destination before calling `uploadFromLocal`.
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cairn-paste-\(UUID().uuidString).\(ext)")
    do {
        try data.write(to: tmpURL, options: .atomic)
    } catch {
        NSSound.beep()
        return
    }
    let size = Int64(data.count)
    Task { @MainActor [weak self] in
        guard let self else {
            try? FileManager.default.removeItem(at: tmpURL)
            return
        }
        let dstPath = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled",
            ext: ext,
            in: target,
            probe: { [weak self] candidate in
                guard let self else { return false }
                return (try? await self.provider.stat(candidate)) != nil
            }
        )
        self.transfers.enqueue(
            source: FSPath(provider: .local, path: tmpURL.path),
            destination: dstPath,
            sizeHint: size
        ) { [weak self] job, progress in
            guard let self else {
                try? FileManager.default.removeItem(at: tmpURL)
                return
            }
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            try await self.provider.uploadFromLocal(
                tmpURL, to: dstPath,
                progress: progress, cancel: job.cancel
            )
        }
    }
}
```

Key changes:
- Temp file is written up-front (unchanged).
- Remote naming is deferred into the `Task` so it can `await provider.stat`.
- Probe closure returns `true` iff `stat` succeeds — any error (missing file, permission, network) is treated as "doesn't exist" and we'll race the upload; this matches the existing pattern where remote errors beep/fail on the upload path itself.
- Early temp-file cleanup when `self` is gone before the `Task` body runs (prevents a leaked temp).

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Cairn -destination 'platform=macOS' -quiet build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 3: Manual smoke test**

1. Launch Cairn, open an SSH tab, `cd` into a writable remote folder via the UI.
2. On macOS: `Cmd+Shift+4`, capture a screenshot to clipboard.
3. In the remote tab, press `Cmd+V` — expect `Untitled.png` to land.
4. Immediately `Cmd+V` again (within 1 second) — expect `Untitled 2.png` to land, **no overwrite**.
5. Refresh; expect both files visible with distinct mtimes/sizes.

Document the manual result in the commit message if the test rig doesn't automate it.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "fix(ssh): paste image probes SFTP stat, never overwrites

Replace epoch-seconds filename in pasteImageToSSH with a stat-probing
'Untitled' → 'Untitled 2' loop via RemoteNameResolver. Two pastes in
the same second (or a pre-existing Untitled-<n>) no longer clobber an
existing remote file — reported by Codex adversarial review."
```

---

# Section B — Preview inspector regression (high)

Commit `1feec22` hard-disabled `.inspector` and removed its toolbar toggle for every tab/window, not just the broken remote path. Local-file preview (which worked prior to that commit) is now gone entirely.

Fix: restore the `.inspector` modifier and toolbar toggle verbatim from `origin/main~5`; scope the "preview doesn't work yet" message to the remote branch **inside** `PreviewPaneView`.

## Task B1: Restore inspector modifier and toolbar toggle

**Files:**
- Modify: `apps/Sources/ContentView.swift:16-35` and `apps/Sources/ContentView.swift:144-157`

- [ ] **Step 1: Flip `showInspector` default back to `true`**

Current:

```swift
/// Preview pane is temporarily disabled. Kept the state here so future
/// re-enable only needs to restore the `.inspector` modifier and the
/// toolbar toggle. Do NOT flip this to true until the remote-file
/// preview path is settled.
@State private var showInspector: Bool = false
```

Replace with:

```swift
@State private var showInspector: Bool = true
```

- [ ] **Step 2: Restore the `.inspector` modifier**

In `body`, between `detail: { detailColumn }` and `.navigationTitle(...)`, the current code has:

```swift
} detail: {
    detailColumn
}
// Inspector (preview pane) disabled for now. Re-enable by
// restoring `.inspector(isPresented: $showInspector) { … }` and
// the toolbar toggle in `mainToolbar`.
.navigationTitle({
```

Replace the stale comment block with the modifier:

```swift
} detail: {
    detailColumn
}
.inspector(isPresented: $showInspector) {
    if let tab {
        PreviewPaneView(preview: tab.preview)
    } else {
        Color.clear
    }
}
.navigationTitle({
```

- [ ] **Step 3: Restore the toolbar toggle**

Replace the current `mainToolbar` body:

```swift
@ToolbarContentBuilder
private var mainToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
        TransferHudChip(controller: app.transfers)
    }
    ToolbarItem(placement: .primaryAction) {
        Button(action: toggleSplit) {
            Image(systemName: dualPane.isSplit ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
        }
        .help(dualPane.isSplit ? "Collapse Split View" : "Split View (⌘⇧D)")
        // Shortcut lives on the View menu entry so it doesn't double-fire.
    }
    // Preview pane toggle intentionally removed — inspector is disabled.
}
```

With:

```swift
@ToolbarContentBuilder
private var mainToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
        TransferHudChip(controller: app.transfers)
    }
    ToolbarItem(placement: .primaryAction) {
        Button(action: toggleSplit) {
            Image(systemName: dualPane.isSplit ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
        }
        .help(dualPane.isSplit ? "Collapse Split View" : "Split View (⌘⇧D)")
        // Shortcut lives on the View menu entry so it doesn't double-fire.
    }
    ToolbarItem(placement: .primaryAction) {
        Button(action: { showInspector.toggle() }) {
            Image(systemName: "sidebar.right")
        }
        .help("Toggle Preview Pane")
        .keyboardShortcut("i", modifiers: [.command, .option])
    }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `xcodebuild -scheme Cairn -destination 'platform=macOS' -quiet build 2>&1 | tail -20`
Expected: build succeeds.

## Task B2: Scope "preview unsupported" to remote inside `PreviewPaneView`

**Files:**
- Modify: `apps/Sources/Views/Preview/PreviewPaneView.swift`

- [ ] **Step 1: Read the current file**

Run: `wc -l apps/Sources/Views/Preview/PreviewPaneView.swift` and `head -40 apps/Sources/Views/Preview/PreviewPaneView.swift` to confirm current render entry point. Locate the `body` closure. Expect a top-level dispatch on `preview.focus` or `preview.remoteFocus`.

- [ ] **Step 2: Add a provider-aware short-circuit at the top of `body`**

At the very start of `var body: some View`, before the existing content, add:

```swift
if preview.isRemoteFocus {
    remotePreviewUnsupportedPlaceholder
} else {
    // existing body content unchanged
    …
}
```

Where `isRemoteFocus` is a computed property on `PreviewModel`:

```swift
// In apps/Sources/ViewModels/PreviewModel.swift, near the existing
// `focus` / `setRemoteFocus` members:
var isRemoteFocus: Bool { remoteFocus != nil }
```

(If `remoteFocus` is named differently in the model, match the existing symbol — grep for `setRemoteFocus` to find the backing storage.)

And the placeholder view, added as a private computed on `PreviewPaneView`:

```swift
@ViewBuilder
private var remotePreviewUnsupportedPlaceholder: some View {
    VStack(spacing: 12) {
        Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 32, weight: .regular))
            .foregroundStyle(.secondary)
        Text("Preview not available for remote files yet")
            .font(.headline)
        Text("Open the file or use Quick Look from the context menu.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 260)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
}
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -scheme Cairn -destination 'platform=macOS' -quiet build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 4: Run existing preview tests**

Run: `xcodebuild test -scheme Cairn -destination 'platform=macOS' -only-testing:CairnTests/PreviewModelTests 2>&1 | tail -30`
Expected: existing `PreviewModelTests` pass unchanged.

- [ ] **Step 5: Manual smoke test**

1. Open Cairn, local tab. Select a text file. Expect preview to render in the inspector. ✅
2. Cmd+Option+I toggles inspector off/on. ✅
3. Open an SSH tab. Select a remote file. Expect the "Preview not available for remote files yet" placeholder (not a broken/empty pane). ✅
4. Split view (⌘⇧D) with one local + one remote pane; switch active pane. Inspector content reflects the active pane.

- [ ] **Step 6: Commit**

```bash
git add apps/Sources/ContentView.swift \
        apps/Sources/Views/Preview/PreviewPaneView.swift \
        apps/Sources/ViewModels/PreviewModel.swift
git commit -m "fix(ui): restore preview inspector for local; scope remote-only disable

Revert the blanket .inspector removal from 1feec22. Local previews
work again and the ⌘⌥I toggle is back in the toolbar. Remote tabs
now render an explicit 'preview unavailable' placeholder inside
PreviewPaneView instead of hiding the entire inspector. Reported by
Codex adversarial review."
```

---

# Section C — Pane-focus monitor leaks across windows (medium)

`PaneColumn` installs `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` and only compares the event's converted point against `frameInWindow`. Local monitors are application-wide, so **every** window's panes receive **every** window's clicks; if two windows happen to sit such that a click in window A hits a pane's frame in window B, window B's `activeSide` silently flips.

Fix: capture host `NSWindow` when the pane appears and hard-gate the monitor on `event.window === hostWindow`.

## Task C1: Add `WindowAccessor` NSViewRepresentable

**Files:**
- Create: `apps/Sources/Views/WindowAccessor.swift`

- [ ] **Step 1: Write the file**

```swift
// apps/Sources/Views/WindowAccessor.swift
import SwiftUI
import AppKit

/// Publishes its host NSWindow through a @Binding. Drop into a
/// `.background(WindowAccessor(window: $hostWindow))` to capture the
/// containing window from a SwiftUI view — useful for any AppKit
/// bridging that needs to disambiguate multi-window state
/// (event monitors, global hotkey targets, NSPanel anchoring).
///
/// The window isn't known until the view is attached to the window
/// hierarchy, so the representable sets it asynchronously on
/// `makeNSView` and whenever `viewDidMoveToWindow` fires.
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let v = TrackerView()
        v.onWindowChange = { self.window = $0 }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TrackerView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Cairn -destination 'platform=macOS' -quiet build 2>&1 | tail -20`
Expected: build succeeds (no references yet).

## Task C2: Gate `PaneColumn`'s mouse-down monitor on host window

**Files:**
- Modify: `apps/Sources/Views/PaneColumn.swift:29-48` and `apps/Sources/Views/PaneColumn.swift:94-113`

- [ ] **Step 1: Add `hostWindow` state**

Find:

```swift
@State private var frameInWindow: CGRect = .zero
@State private var mouseDownMonitor: Any?
```

Replace with:

```swift
@State private var frameInWindow: CGRect = .zero
@State private var mouseDownMonitor: Any?
/// Host NSWindow captured via WindowAccessor. The click-to-focus monitor
/// is application-wide (NSEvent.addLocalMonitorForEvents), so we gate
/// every event on `event.window === hostWindow` — otherwise clicks in
/// window A can flip activeSide in window B if their pane frames overlap.
@State private var hostWindow: NSWindow?
```

- [ ] **Step 2: Install `WindowAccessor` in the background stack**

Find the `.background(GeometryReader { ... })` modifier on `paneStack`. Replace it with a two-layer background:

```swift
.background(
    GeometryReader { proxy in
        Color.clear
            .onAppear { frameInWindow = proxy.frame(in: .global) }
            .onChange(of: proxy.frame(in: .global)) { _, new in
                frameInWindow = new
            }
    }
)
.background(WindowAccessor(window: $hostWindow))
```

(Two chained `.background` modifiers stack — the `WindowAccessor` tracker view sits behind the GeometryReader and carries zero visual weight.)

- [ ] **Step 3: Gate the monitor**

Current:

```swift
private func installMouseDownMonitor() {
    guard mouseDownMonitor == nil else { return }
    mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
        guard let window = event.window,
              let contentView = window.contentView else { return event }
        let contentPoint = contentView.convert(event.locationInWindow, from: nil)
        let swiftUIPoint = CGPoint(
            x: contentPoint.x,
            y: contentView.frame.height - contentPoint.y
        )
        if frameInWindow.contains(swiftUIPoint) {
            onFocus()
        }
        return event
    }
}
```

Replace with:

```swift
private func installMouseDownMonitor() {
    guard mouseDownMonitor == nil else { return }
    mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
        // Local event monitors are app-wide. Hard-gate on host window
        // identity — otherwise clicks in another window whose pane
        // frame coordinates collide with ours would silently flip
        // activeSide on the wrong window.
        guard let eventWindow = event.window,
              let host = hostWindow,
              eventWindow === host,
              let contentView = eventWindow.contentView else { return event }
        let contentPoint = contentView.convert(event.locationInWindow, from: nil)
        let swiftUIPoint = CGPoint(
            x: contentPoint.x,
            y: contentView.frame.height - contentPoint.y
        )
        if frameInWindow.contains(swiftUIPoint) {
            onFocus()
        }
        return event
    }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `xcodebuild -scheme Cairn -destination 'platform=macOS' -quiet build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 5: Manual multi-window regression test**

1. Launch Cairn. Open two windows (`File → New Window`, or `⌘N`).
2. In window A, split view (⌘⇧D). Focus the right pane.
3. In window B, split view (⌘⇧D). Focus the right pane.
4. Click the **left** pane in window A.
   - Expect: window A's `activeSide` becomes `.left`.
   - Expect: window B's `activeSide` stays `.right` (NOT flipped).
5. Click the **right** pane in window B.
   - Expect: window B's `activeSide` becomes `.right` (already was).
   - Expect: window A's `activeSide` stays `.left`.
6. Resize windows so panes overlap in screen space — repeat steps 4-5, confirm no cross-window focus leakage.

Prior to the fix, steps 4 / 5 would flip the other window's `activeSide` whenever the click's window-local coordinates happened to fall inside the other window's cached pane frame.

- [ ] **Step 6: Commit**

```bash
git add apps/Sources/Views/WindowAccessor.swift \
        apps/Sources/Views/PaneColumn.swift
git commit -m "fix(ui): gate pane-focus NSEvent monitor on host window

NSEvent.addLocalMonitorForEvents is application-wide, so clicks in one
window were converted and hit-tested against another window's cached
pane frame — flipping activeSide in the wrong window when frames
happened to overlap. Capture the host NSWindow via a new
WindowAccessor NSViewRepresentable and short-circuit unless
event.window === hostWindow. Reported by Codex adversarial review."
```

---

## Self-review checklist (run after all tasks)

- [ ] **Spec coverage:** three findings (A, B, C) each have a section that ends in a commit — no gap.
- [ ] **No placeholders:** every code block above contains complete Swift; no TBD/TODO/"similar to above".
- [ ] **Type consistency:** `RemoteNameResolver.uniqueRemotePath(base:ext:in:probe:)` signature is identical in Task A1 (definition), A2 (tests), and A3 (call site). `WindowAccessor(window:)` signature identical in Task C1 and C2.
- [ ] **Build clean:** run once more at the end — `xcodebuild -scheme Cairn -destination 'platform=macOS' build 2>&1 | tail -10`.
- [ ] **Full test suite green:** `xcodebuild test -scheme Cairn -destination 'platform=macOS' 2>&1 | tail -20`.
- [ ] **Re-run Codex adversarial review:** `/codex:adversarial-review --base origin/main~5` on the new HEAD should flag zero `[high]` findings for these paths.
