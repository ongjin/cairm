# Cairn Phase 1 UX Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commit message policy:** Do NOT add `Co-Authored-By:` trailers, WOZCODE/Claude/Anthropic references, or any AI/tool footer. Finish the commit message body and stop.

**Goal:** Fix high-impact regressions and fill the biggest UX gaps between the current Cairn build and a credible Finder replacement: tab cross-contamination, broken ⌘⇧. hidden-toggle, empty command palette, missing right inspector toggle, stale ⌘K button, inconsistent tab bar, no Settings scene, hidden files rendering identical to visible ones, a second glass-theme pass, and a search-perf pass on the Rust side.

**Architecture:**
- **Swift app layer** — Surgical fixes to FileListCoordinator (bindings refresh), ContentView (onChange wiring + inspector toggle + toolbar trim), TabBarView/TabChip (layout), FileListRowView (hidden-file opacity), a new Settings scene (SwiftUI `Settings` block), and a second CairnTheme.glass refresh.
- **Rust engine layer** — In-memory LRU on IndexStore.list_all() to cut redb full-scan cost, plus a diagnostic log line when `ffi_index_open` fails so the palette's silent no-result case is debuggable.

**Tech Stack:** Swift 5.10 / SwiftUI with `@Observable`, AppKit `NSTableView` via `NSViewRepresentable`, `NSVisualEffectView`, macOS 14+. Rust 1.88 workspace with `nucleo-matcher`, `tree-sitter`, `redb`, swift-bridge FFI.

---

## File Structure

- `apps/Sources/Views/FileList/FileListCoordinator.swift` — mutable bindings + `updateBindings(...)` method.
- `apps/Sources/Views/FileList/FileListView.swift` — call `updateBindings` inside `updateNSView`.
- `apps/Sources/ContentView.swift` — remove ⌘K toolbar button; add inspector toggle; fix `showHidden` onChange to reload folder; thread inspector visibility state.
- `apps/Sources/Views/FileList/FileListRowView.swift` — render hidden files at reduced opacity.
- `apps/Sources/Views/Tabs/TabBarView.swift` + `TabChip.swift` — unified chip sizing, spacing, selection pill consistent with sidebar.
- `apps/Sources/Theme/CairnTheme.swift` — second pass on `.glass`: bluer sidebar, more translucency, bluer accent.
- `apps/Sources/Views/Sidebar/SidebarView.swift` — adjust gradient/tint values to match theme revision.
- `apps/Sources/CairnApp.swift` — add `Settings { CairnSettingsView() }` scene; register ⌘, implicitly.
- `apps/Sources/Views/Settings/CairnSettingsView.swift` (new) — tabbed settings UI.
- `apps/Sources/Services/SettingsStore.swift` (new) — `@Observable` UserDefaults-backed store.
- `apps/Sources/App/AppModel.swift` — expose `SettingsStore` via environment.
- `apps/Sources/ViewModels/CommandPaletteModel.swift` — add a `FolderModel`-backed fallback when IndexService is nil so bare-text queries show current-folder matches.
- `apps/CairnTests/FileListCoordinatorTests.swift` — new test covering `updateBindings` semantics.
- `apps/CairnTests/CommandPaletteModelTests.swift` — add fallback-path test.
- `crates/cairn-index/src/store.rs` — cached `list_all_cached()` with generation counter + eviction on write.
- `crates/cairn-ffi/src/index.rs` — log on `ffi_index_open` failure (stderr, structured), bump version in return path.
- `crates/cairn-index/tests/store_cache.rs` — new Rust test for cache invalidation.

---

## Task 1: FileListCoordinator bindings refresh (P0 bug: tab cross-contamination)

**Root cause:** `FileListView` is an `NSViewRepresentable` whose `makeCoordinator()` fires once. The Coordinator holds `let folder: FolderModel` and `let onActivate: (FileEntry) -> Void` captured at first render. When the user ⌘T to a second tab and double-clicks a folder, `self.onActivate(entry)` still points at Tab A's closure → Tab A navigates, not Tab B. Sort descriptor writes and selection writes have the same bug (they target the stale FolderModel reference).

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift`
- Modify: `apps/Sources/Views/FileList/FileListView.swift`
- Create: `apps/CairnTests/FileListCoordinatorTests.swift`

- [ ] **Step 1.1: Write the failing test**

Create `apps/CairnTests/FileListCoordinatorTests.swift`:

```swift
import XCTest
@testable import Cairn

@MainActor
final class FileListCoordinatorTests: XCTestCase {
    func test_updateBindings_swapsActivateClosure() {
        let engine = CairnEngine()
        let folderA = FolderModel(engine: engine)
        let folderB = FolderModel(engine: engine)

        let entry = FileEntryFixtures.dir(name: "Documents", path: "/Users/x/Documents")
        folderA.setEntries([entry])
        folderB.setEntries([entry])

        var aActivated = 0
        var bActivated = 0

        let coord = FileListCoordinator(
            folder: folderA,
            onActivate: { _ in aActivated += 1 },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )

        // Simulate first render: Tab A active.
        coord.fireActivate(entry: entry)
        XCTAssertEqual(aActivated, 1)
        XCTAssertEqual(bActivated, 0)

        // Simulate tab switch: SwiftUI reuses coordinator, calls updateBindings.
        coord.updateBindings(
            folder: folderB,
            onActivate: { _ in bActivated += 1 },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )

        coord.fireActivate(entry: entry)
        XCTAssertEqual(aActivated, 1)    // A must NOT fire again
        XCTAssertEqual(bActivated, 1)    // B must now fire
    }

    func test_updateBindings_swapsFolderReference() {
        let engine = CairnEngine()
        let folderA = FolderModel(engine: engine)
        let folderB = FolderModel(engine: engine)

        let coord = FileListCoordinator(
            folder: folderA,
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )
        XCTAssertTrue(coord.folderRefForTest === folderA)

        coord.updateBindings(
            folder: folderB,
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )
        XCTAssertTrue(coord.folderRefForTest === folderB)
    }
}

enum FileEntryFixtures {
    static func dir(name: String, path: String) -> FileEntry {
        // FileEntry is a Rust-bridged struct. Use the public init exposed by the
        // bridge; fields here mirror the minimum required for tests.
        var e = FileEntry()
        // swift-bridge usually emits public `name: RustString`; tests interact
        // via the bridge helpers. If the type is opaque in tests, replace this
        // helper with whatever constructor the existing tests (see
        // FolderModelTests.swift) use to build a fixture entry.
        return e
    }
}
```

If `FileEntry` cannot be constructed directly in tests (opaque swift-bridge type), replace `FileEntryFixtures.dir` with the same helper used in `apps/CairnTests/FolderModelTests.swift` (read that file first and copy the exact fixture pattern — the controller has confirmed FolderModel tests already build fixture entries successfully).

- [ ] **Step 1.2: Run the test — should fail to compile**

```bash
cd /Users/cyj/workspace/personal/cairn
(cd apps && xcodegen generate)
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn test \
  -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Expected: compile errors — `updateBindings`, `fireActivate`, `folderRefForTest` don't exist on `FileListCoordinator`.

- [ ] **Step 1.3: Convert Coordinator bindings to mutable + add updateBindings**

In `apps/Sources/Views/FileList/FileListCoordinator.swift`:

1. Change these from `let` to `var` (keep `private`):
   - `private var folder: FolderModel`
   - `private var onActivate: (FileEntry) -> Void`
   - `private var onAddToPinned: (FileEntry) -> Void`
   - `private var isPinnedCheck: (FileEntry) -> Bool`
   - `private var onSelectionChanged: (FileEntry?) -> Void`

2. Add method (place it right after `attach(table:)`):

```swift
/// Refresh captured bindings when SwiftUI re-renders FileListView with a
/// different Tab. SwiftUI only calls `makeCoordinator()` once per view
/// identity, so without this the coordinator keeps pointing at the very
/// first Tab's FolderModel / navigate closure — double-clicks from a
/// later tab then route back to the original tab. If the FolderModel
/// identity changed, we also re-run attach(table:) so sort indicator and
/// selection state reflect the new tab's state.
func updateBindings(folder: FolderModel,
                    onActivate: @escaping (FileEntry) -> Void,
                    onAddToPinned: @escaping (FileEntry) -> Void,
                    isPinnedCheck: @escaping (FileEntry) -> Bool,
                    onSelectionChanged: @escaping (FileEntry?) -> Void) {
    let folderChanged = self.folder !== folder
    self.folder = folder
    self.onActivate = onActivate
    self.onAddToPinned = onAddToPinned
    self.isPinnedCheck = isPinnedCheck
    self.onSelectionChanged = onSelectionChanged
    if folderChanged, let t = self.table {
        attach(table: t)
    }
}

#if DEBUG
/// Test-only hook to invoke the current onActivate without routing through
/// AppKit. Keeps unit tests decoupled from NSTableView.
func fireActivate(entry: FileEntry) { onActivate(entry) }

/// Test-only identity probe for asserting folder swap behaviour.
var folderRefForTest: FolderModel { folder }
#endif
```

- [ ] **Step 1.4: Call updateBindings from updateNSView**

In `apps/Sources/Views/FileList/FileListView.swift`, inside `updateNSView(_:context:)`, insert the refresh call at the TOP (before `setEntries`):

```swift
func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let table = scroll.documentView as? FileListNSTableView else { return }
    context.coordinator.updateBindings(
        folder: folder,
        onActivate: onActivate,
        onAddToPinned: onAddToPinned,
        isPinnedCheck: isPinnedCheck,
        onSelectionChanged: onSelectionChanged
    )
    context.coordinator.setEntries(entries, searchRoot: searchRoot)
    context.coordinator.setFolderColumnVisible(folderColumnVisible)
    context.coordinator.setFolderRoot(folderRoot)
    context.coordinator.setGitSnapshot(gitSnapshot)
    context.coordinator.applyModelSnapshot(table: table)
}
```

- [ ] **Step 1.5: Run tests — should pass**

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn test \
  -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Expected: new `FileListCoordinatorTests` pass, all existing tests still pass.

- [ ] **Step 1.6: Commit**

```bash
git add apps/Sources/Views/FileList/FileListCoordinator.swift \
        apps/Sources/Views/FileList/FileListView.swift \
        apps/CairnTests/FileListCoordinatorTests.swift
git commit -m "fix(file-list): refresh coordinator bindings on render

NSViewRepresentable only calls makeCoordinator() once, so
FileListCoordinator captured the first active tab's FolderModel and
navigate closure forever. ⌘T then double-clicking a folder in the new
tab routed the navigation back to the original tab (whose currentFolder
changed while the new tab sat still).

Switch folder/onActivate/onAddToPinned/isPinnedCheck/onSelectionChanged
from let to var and refresh them in updateNSView via updateBindings().
Re-run attach(table:) when the FolderModel identity actually changed so
sort indicator + selection reflect the new tab's state."
```

---

## Task 2: Fix ⌘⇧. hidden-file toggle (P0 bug: no visible effect)

**Root cause:** `ContentView.onChange(of: app.showHidden)` only calls `triggerSearchRefresh()`. When the user isn't in active search, no reload happens — the Rust engine's `list_directory` returns the pre-toggle filter because it's only called on folder load.

**Files:**
- Modify: `apps/Sources/ContentView.swift`

- [ ] **Step 2.1: Update the onChange handler**

In `apps/Sources/ContentView.swift` around line 56, replace:

```swift
.onChange(of: app.showHidden) { _, _ in triggerSearchRefresh() }
```

with:

```swift
.onChange(of: app.showHidden) { _, _ in
    if let tab, let url = tab.currentFolder {
        Task { await tab.folder.load(url) }
    }
    triggerSearchRefresh()
}
```

- [ ] **Step 2.2: Build**

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
  -configuration Debug -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2.3: Commit**

```bash
git add apps/Sources/ContentView.swift
git commit -m "fix(content): reload folder when toggling hidden files

⌘⇧. flipped app.showHidden and poked the engine flag, but ContentView's
onChange only kicked the search refresher — outside search mode the
file list kept the pre-toggle view until manual reload.

Reload the active tab's folder alongside the search refresh so the
shortcut has a visible effect everywhere."
```

---

## Task 3: Hidden files rendered with reduced opacity

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListRowView.swift`

- [ ] **Step 3.1: Read the row view**

Open `apps/Sources/Views/FileList/FileListRowView.swift` and find the main body / cell-composition function. Identify how the filename string is rendered (likely `Text(entry.name.toString())` inside an `HStack` or similar).

- [ ] **Step 3.2: Add a hidden-aware opacity modifier**

Inside that view, compute `let isHidden = entry.name.toString().hasPrefix(".")` and apply `.opacity(isHidden ? 0.55 : 1.0)` to the ROW's top-level view (so both icon and text dim together). The icon column also needs to dim — use `.opacity` on the enclosing container, not individual subviews, to keep a single hidden-state source of truth.

Example patch shape — adapt to the file's actual structure:

```swift
private var body: some View {
    let isHidden = entry.name.toString().hasPrefix(".")
    return HStack(spacing: 6) {
        // … existing icon / text / columns
    }
    .opacity(isHidden ? 0.55 : 1.0)
}
```

If the row is an NSTableCellView-backed implementation rather than pure SwiftUI, the equivalent is to set `alphaValue = isHidden ? 0.55 : 1.0` on the cell's content view. Read the file first to determine which style is in use and follow the same style — do not port between them.

- [ ] **Step 3.3: Build + verify visually**

```bash
./scripts/build-rust.sh 2>/dev/null || true
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
  -configuration Debug -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

Expected: `** BUILD SUCCEEDED **`. The controller will eyeball visually.

- [ ] **Step 3.4: Commit**

```bash
git add apps/Sources/Views/FileList/FileListRowView.swift
git commit -m "feat(file-list): dim hidden files to 0.55 opacity

Hidden entries (name.startsWith('.')) render at reduced opacity so the
user can distinguish them at a glance when ⌘⇧. is on."
```

---

## Task 4: Remove ⌘K button from the toolbar

**Files:**
- Modify: `apps/Sources/ContentView.swift`

- [ ] **Step 4.1: Delete the ⌘K ToolbarItem**

In `apps/Sources/ContentView.swift`, inside `@ToolbarContentBuilder private var mainToolbar`, locate the `ToolbarItem(placement: .primaryAction) { Button(action: { palette.open() }) { ... } }` block (around line 197–214) and delete it entirely. The palette still opens via ⌘K (bound in `CairnApp.FindCommands`) — only the button UI is removed.

- [ ] **Step 4.2: Build + commit**

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
  -configuration Debug -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
git add apps/Sources/ContentView.swift
git commit -m "style(toolbar): remove redundant ⌘K palette button

Keyboard shortcut ⌘K (CairnApp.FindCommands) is the canonical entry
point; the dedicated toolbar button duplicated the affordance and
cluttered the header. Menu item 'Open Palette' still exposes it for
discoverability."
```

---

## Task 5: Right inspector (preview pane) toggle

SwiftUI's `NavigationSplitView` accepts a `NavigationSplitViewVisibility` binding on the `columnVisibility:` initialiser parameter (macOS 13+). We drive inspector visibility with a `@State` held on ContentView (per window) and flip it from a new toolbar button. The preview pane is the `detail` column.

**Files:**
- Modify: `apps/Sources/ContentView.swift`

- [ ] **Step 5.1: Add inspector visibility state**

Near the top of `ContentView` (next to `@State private var palette = CommandPaletteModel()`), add:

```swift
@State private var detailVisibility: NavigationSplitViewVisibility = .all
```

- [ ] **Step 5.2: Bind it to NavigationSplitView**

Replace `NavigationSplitView { ... } content: { ... } detail: { ... }` with:

```swift
NavigationSplitView(columnVisibility: $detailVisibility) {
    SidebarView(app: app, scene: scene)
} content: {
    contentColumn
} detail: {
    if let tab {
        PreviewPaneView(preview: tab.preview)
    } else {
        Color.clear
    }
}
```

- [ ] **Step 5.3: Add a toolbar button to toggle the detail (inspector)**

In `mainToolbar`, add a new `ToolbarItem(placement: .primaryAction)` AFTER the navigation group:

```swift
ToolbarItem(placement: .primaryAction) {
    Button(action: {
        detailVisibility = (detailVisibility == .all) ? .doubleColumn : .all
    }) {
        Image(systemName: detailVisibility == .all
              ? "sidebar.right"
              : "sidebar.squares.right")
    }
    .help("Toggle Preview Pane")
    .keyboardShortcut("i", modifiers: [.command, .option])
}
```

Rationale for `.doubleColumn` rather than `.detailOnly`: `.doubleColumn` shows sidebar + content only, hiding detail. That matches the user's ask ("open/close" the right pane). `.all` brings detail back.

- [ ] **Step 5.4: Build + commit**

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
  -configuration Debug -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
git add apps/Sources/ContentView.swift
git commit -m "feat(content): add preview-pane toggle button (⌥⌘I)

Drives NavigationSplitView columnVisibility between .all (sidebar +
content + detail) and .doubleColumn (sidebar + content). Toolbar
button + ⌥⌘I shortcut mirrors Finder's 'Show/Hide Preview'."
```

---

## Task 6: Unify tab bar appearance

**Diagnosis (from screenshots):** The blue-pill active tab has a different outline radius, vertical padding, and border thickness than the inactive tab. The `+` button sits on a different baseline. Goal: single geometry, consistent with the refreshed glass theme.

**Files:**
- Modify: `apps/Sources/Views/Tabs/TabBarView.swift`
- Modify: `apps/Sources/Views/Tabs/TabChip.swift`

- [ ] **Step 6.1: Normalise TabChip geometry**

Replace the `.background` + `.overlay` pair in `TabChip.body` with a single continuous-corner rounded rectangle so active/inactive chips share everything but fill:

```swift
.padding(.horizontal, 10)
.padding(.vertical, 5)
.background(
    RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        .fill(isActive ? theme.accentMuted : Color.secondary.opacity(0.08))
)
.overlay(
    RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        .stroke(isActive ? theme.accent.opacity(0.35) : Color.clear, lineWidth: 0.5)
)
.contentShape(Rectangle())
.onTapGesture(perform: onActivate)
.onHover { hovering = $0 }
.frame(minWidth: 120, maxWidth: 180)
```

Changes vs current file:
- Padding vertical 4 → 5 (matches sidebar row rhythm)
- Corner radius 6 → `theme.cornerRadius` (currently 8)
- Inactive fill: `Color.clear` → `Color.secondary.opacity(0.08)` (inactive chip now has a visible frame)
- `minWidth: 120` so short names don't collapse the chip

- [ ] **Step 6.2: Normalise TabBarView spacing and + button**

In `TabBarView.swift`, update the `+` Button and surrounding spacing:

```swift
HStack(spacing: 8) {
    ForEach(scene.tabs) { tab in
        TabChip(
            label: tab.currentFolder?.lastPathComponent ?? "Untitled",
            isActive: tab.id == scene.activeTabID,
            onActivate: { scene.activeTabID = tab.id },
            onClose: { scene.closeTab(tab.id) }
        )
    }
    Button(action: { scene.newTab() }) {
        Image(systemName: "plus")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
    }
    .buttonStyle(.plain)
    Spacer()
}
.padding(.horizontal, 10)
.padding(.vertical, 5)
.frame(height: 36)
.background(.thinMaterial)
```

Changes:
- HStack spacing 6 → 8
- `+` gets its own 24×24 pill matching the chip radius
- Bar height 32 → 36 for clearance
- Inner horizontal padding 8 → 10 aligned with content column

- [ ] **Step 6.3: Build + commit**

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
  -configuration Debug -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
git add apps/Sources/Views/Tabs/TabBarView.swift \
        apps/Sources/Views/Tabs/TabChip.swift
git commit -m "style(tabs): unify chip geometry and + button

Active and inactive chips now share padding / radius / stroke shape —
only the fill differs. Inactive chips pick up a faint secondary fill
so they're visible at rest, and the + button gets the same 8pt radius
so the bar reads as a single toolbar rather than three shapes."
```

---

## Task 7: Command palette — surface results when IndexService is nil or empty

**Root cause recap:** Every palette mode routes through `tab.index?.queryXxx() ?? []`. When `ffi_index_open` fails (sandbox / redb path) or the index is mid-build after a navigation, all queries return empty and the user sees a silent empty palette. This task does two things:
  1. **Rust-side:** emit a `eprintln!` diagnostic when `ffi_index_open` fails, so the cause is visible in Console.app / xcode log.
  2. **Swift-side:** when `tab.index` is nil AND the user is in bare-text (fuzzy) mode, fall back to filtering `tab.folder.sortedEntries` with a local nucleo-equivalent scorer so something shows up.

**Files:**
- Modify: `crates/cairn-ffi/src/index.rs`
- Modify: `apps/Sources/ViewModels/CommandPaletteModel.swift`
- Modify: `apps/CairnTests/CommandPaletteModelTests.swift`

- [ ] **Step 7.1: Add failure diagnostic to ffi_index_open**

In `crates/cairn-ffi/src/index.rs`, locate the body of `pub fn ffi_index_open(root: String) -> u64`. Wrap the error branch(es) so that any failure path logs before returning 0. Example pattern (adapt to the actual control flow — read the function first):

```rust
pub fn ffi_index_open(root: String) -> u64 {
    let root_p = PathBuf::from(&root);
    let store = match open_store(&root_p) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("cairn: ffi_index_open failed for {root:?}: {e}");
            return 0;
        }
    };
    // … rest unchanged
}
```

Every early-return that means "failure" should log with a `cairn: ffi_index_open …` prefix so the user (or controller) can grep for it. Do not change the return type or calling convention.

- [ ] **Step 7.2: Write the palette fallback test**

In `apps/CairnTests/CommandPaletteModelTests.swift`, add:

```swift
func test_fuzzyFallback_usesFolderEntries_whenIndexIsNil() {
    let engine = CairnEngine()
    let folder = FolderModel(engine: engine)
    folder.setEntries([
        FileEntryFixtures.file(name: "Readme.md", path: "/tmp/Readme.md"),
        FileEntryFixtures.file(name: "main.swift", path: "/tmp/main.swift"),
        FileEntryFixtures.file(name: "notes.txt", path: "/tmp/notes.txt")
    ])

    let model = CommandPaletteModel()
    model.open()
    model.query = "swif"
    let hits = model.fallbackFuzzyHits(folder: folder)

    XCTAssertEqual(hits.map(\.pathRel), ["main.swift"])
}
```

`fallbackFuzzyHits(folder:)` doesn't exist yet — the test will fail to compile. Use the same `FileEntryFixtures` helper from `FolderModelTests` or `FileListCoordinatorTests`.

- [ ] **Step 7.3: Run test — should fail to compile**

```bash
(cd apps && xcodegen generate)
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn test \
  -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Expected: compile failure — `fallbackFuzzyHits` not found.

- [ ] **Step 7.4: Implement the fallback in CommandPaletteModel**

Add a method to `CommandPaletteModel.swift`:

```swift
/// Filter the current folder's entries by a fuzzy substring match on
/// filename. Used as a fallback when IndexService is unavailable so the
/// palette at least surfaces the visible folder rather than going empty.
func fallbackFuzzyHits(folder: FolderModel) -> [FileHit] {
    let raw = query.lowercased()
    guard !raw.isEmpty else { return [] }
    let entries = folder.entries
    return entries.compactMap { entry in
        let name = entry.name.toString().lowercased()
        return name.contains(raw)
            ? FileHit(pathRel: entry.name.toString(), score: 0)
            : nil
    }
}
```

(Simple substring — nucleo is used index-side; replicating it in-proc Swift isn't worth the dep for the fallback case. Substring is good enough when the folder is small.)

Wire it into the existing fuzzy path. In the same file, find the block that returns `tab.index?.queryFuzzy(raw) ?? []` and change it to:

```swift
if let results = tab.index?.queryFuzzy(raw), !results.isEmpty {
    return results
}
return fallbackFuzzyHits(folder: tab.folder)
```

(Only the bare-text / fuzzy branch gets the fallback. `@` / `/` / `#` / `>` keep returning empty when no index — those rely on symbol/content/git/command state that we can't synthesise from FolderModel.)

- [ ] **Step 7.5: Run tests — should pass**

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn test \
  -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
cargo test --workspace
```

Expected: both pass. Rust tests were already at 0 failures; Swift adds one new passing test.

- [ ] **Step 7.6: Commit**

```bash
git add crates/cairn-ffi/src/index.rs \
        apps/Sources/ViewModels/CommandPaletteModel.swift \
        apps/CairnTests/CommandPaletteModelTests.swift
git commit -m "fix(palette): fallback fuzzy + diagnose index open failures

Every palette mode was routed through tab.index?.queryXxx() ?? [], so
an ffi_index_open failure (sandbox / redb permission) silently produced
an empty palette with no signal. Log a cairn: ffi_index_open prefixed
error on every failure path and, for bare-text fuzzy only, fall back to
a substring filter over the current folder's entries so the user sees
the tab contents."
```

---

## Task 8: Settings scene (⌘,)

Minimum viable Finder-analogue: General / Appearance / Files / Advanced tabs, backed by a small `@Observable` store on top of `UserDefaults`. Everything here maps to behaviour already present in the app (hidden files, sort, start folder, show git column).

**Files:**
- Create: `apps/Sources/Services/SettingsStore.swift`
- Create: `apps/Sources/Views/Settings/CairnSettingsView.swift`
- Modify: `apps/Sources/App/AppModel.swift`
- Modify: `apps/Sources/CairnApp.swift`
- Modify: `apps/Sources/ContentView.swift` (honour `showGitColumn`)
- Modify: `apps/Sources/Views/FileList/FileListView.swift` (hide Git column when `showGitColumn` is false)

- [ ] **Step 8.1: SettingsStore**

Create `apps/Sources/Services/SettingsStore.swift`:

```swift
import Foundation
import Observation

/// Observable facade over UserDefaults for user-facing settings. Keys live
/// under `com.ongjin.cairn.settings.*` so they don't collide with other
/// AppStorage keys elsewhere.
@Observable
final class SettingsStore {
    enum StartFolder: String, CaseIterable, Identifiable {
        case lastUsed
        case home
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lastUsed: return "Last used folder"
            case .home:     return "Home (~)"
            }
        }
    }

    enum FontSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var pt: CGFloat {
            switch self {
            case .small: return 11
            case .medium: return 12
            case .large: return 14
            }
        }
    }

    private let defaults: UserDefaults

    var startFolder: StartFolder {
        didSet { defaults.set(startFolder.rawValue, forKey: Keys.startFolder) }
    }
    var restoreTabs: Bool {
        didSet { defaults.set(restoreTabs, forKey: Keys.restoreTabs) }
    }
    var fontSize: FontSize {
        didSet { defaults.set(fontSize.rawValue, forKey: Keys.fontSize) }
    }
    var defaultSortField: String {        // "name" | "size" | "modified"
        didSet { defaults.set(defaultSortField, forKey: Keys.defaultSortField) }
    }
    var defaultSortAscending: Bool {
        didSet { defaults.set(defaultSortAscending, forKey: Keys.defaultSortAscending) }
    }
    var showHiddenByDefault: Bool {
        didSet { defaults.set(showHiddenByDefault, forKey: Keys.showHiddenByDefault) }
    }
    var showGitColumn: Bool {
        didSet { defaults.set(showGitColumn, forKey: Keys.showGitColumn) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.startFolder = StartFolder(rawValue: defaults.string(forKey: Keys.startFolder) ?? "") ?? .lastUsed
        self.restoreTabs = defaults.object(forKey: Keys.restoreTabs) as? Bool ?? true
        self.fontSize = FontSize(rawValue: defaults.string(forKey: Keys.fontSize) ?? "") ?? .medium
        self.defaultSortField = defaults.string(forKey: Keys.defaultSortField) ?? "name"
        self.defaultSortAscending = defaults.object(forKey: Keys.defaultSortAscending) as? Bool ?? true
        self.showHiddenByDefault = defaults.bool(forKey: Keys.showHiddenByDefault)
        self.showGitColumn = defaults.object(forKey: Keys.showGitColumn) as? Bool ?? true
    }

    private enum Keys {
        static let startFolder           = "com.ongjin.cairn.settings.startFolder"
        static let restoreTabs           = "com.ongjin.cairn.settings.restoreTabs"
        static let fontSize              = "com.ongjin.cairn.settings.fontSize"
        static let defaultSortField      = "com.ongjin.cairn.settings.defaultSortField"
        static let defaultSortAscending  = "com.ongjin.cairn.settings.defaultSortAscending"
        static let showHiddenByDefault   = "com.ongjin.cairn.settings.showHiddenByDefault"
        static let showGitColumn         = "com.ongjin.cairn.settings.showGitColumn"
    }
}
```

- [ ] **Step 8.2: Expose SettingsStore via AppModel**

In `apps/Sources/App/AppModel.swift`, add `let settings: SettingsStore = SettingsStore()` next to the other lets, and update `bootstrapInitialURL()` to honour `startFolder`:

```swift
let settings: SettingsStore

init(engine: CairnEngine = CairnEngine(),
     bookmarks: BookmarkStore = BookmarkStore(),
     lastFolder: LastFolderStore = LastFolderStore(),
     settings: SettingsStore = SettingsStore()) {
    self.engine = engine
    self.bookmarks = bookmarks
    self.lastFolder = lastFolder
    self.settings = settings
    // … existing mountObserver / sidebar init unchanged
}

func bootstrapInitialURL() -> URL {
    switch settings.startFolder {
    case .home:     return FileManager.default.homeDirectoryForCurrentUser
    case .lastUsed: return lastFolder.load() ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
```

Also apply `showHiddenByDefault` once at init time so the initial folder load respects it:

```swift
self.showHidden = settings.showHiddenByDefault
// engine.setShowHidden called lazily on first toggleShowHidden; initialise now:
engine.setShowHidden(showHidden)
```

- [ ] **Step 8.3: CairnSettingsView**

Create `apps/Sources/Views/Settings/CairnSettingsView.swift`:

```swift
import SwiftUI

struct CairnSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            GeneralPane(settings: app.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearancePane(settings: app.settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            FilesPane(settings: app.settings)
                .tabItem { Label("Files", systemImage: "doc") }
            AdvancedPane()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 360)
    }
}

private struct GeneralPane: View {
    @Bindable var settings: SettingsStore
    var body: some View {
        Form {
            Picker("Start with", selection: $settings.startFolder) {
                ForEach(SettingsStore.StartFolder.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            Toggle("Restore tabs on relaunch", isOn: $settings.restoreTabs)
        }
        .padding(20)
    }
}

private struct AppearancePane: View {
    @Bindable var settings: SettingsStore
    var body: some View {
        Form {
            Picker("Font size", selection: $settings.fontSize) {
                ForEach(SettingsStore.FontSize.allCases) { s in
                    Text(s.rawValue.capitalized).tag(s)
                }
            }
            LabeledContent("Theme") {
                Text("Glass (Blue) — more themes in a future release.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

private struct FilesPane: View {
    @Bindable var settings: SettingsStore
    var body: some View {
        Form {
            Picker("Default sort", selection: $settings.defaultSortField) {
                Text("Name").tag("name")
                Text("Size").tag("size")
                Text("Modified").tag("modified")
            }
            Toggle("Ascending", isOn: $settings.defaultSortAscending)
            Toggle("Show hidden files by default", isOn: $settings.showHiddenByDefault)
            Toggle("Show Git status column", isOn: $settings.showGitColumn)
        }
        .padding(20)
    }
}

private struct AdvancedPane: View {
    var body: some View {
        Form {
            LabeledContent("Index cache") {
                Text("~/Library/Caches/Cairn")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Button("Rebuild Index") {
                // Phase 2 will wire an FFI entry point. For now this is an
                // inert affordance so the Settings layout is finalised.
            }
            .disabled(true)
        }
        .padding(20)
    }
}
```

- [ ] **Step 8.4: Register the Settings scene**

In `apps/Sources/CairnApp.swift`, add a `Settings` scene next to `WindowGroup`:

```swift
var body: some Scene {
    WindowGroup { WindowScene(app: app) }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands { /* existing commands */ }

    Settings {
        CairnSettingsView()
            .environment(app)
            .environment(\.cairnTheme, .glass)
    }
}
```

`Settings { ... }` on macOS automatically wires ⌘, to open the settings window. No extra keyboardShortcut needed.

- [ ] **Step 8.5: Honour `showGitColumn` in FileListView**

Simplest viable wiring: take it as a parameter through the existing call chain. In `apps/Sources/ContentView.swift`, where `fileList(tab:)` constructs `FileListView`, pass `showGitColumn: app.settings.showGitColumn`.

Add the stored property to `FileListView`:

```swift
let showGitColumn: Bool
```

In `makeNSView`, only add the `gitCol` column if `showGitColumn` is true. If toggled at runtime, `updateNSView` needs to add/remove the column:

```swift
func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let table = scroll.documentView as? FileListNSTableView else { return }
    context.coordinator.updateBindings(...)  // from Task 1
    // Sync Git column visibility with current setting.
    let hasGit = table.tableColumn(withIdentifier: .git) != nil
    if showGitColumn && !hasGit {
        let gitCol = NSTableColumn(identifier: .git)
        gitCol.title = "Git"; gitCol.minWidth = 28; gitCol.width = 40
        table.addTableColumn(gitCol)
    } else if !showGitColumn && hasGit, let col = table.tableColumn(withIdentifier: .git) {
        table.removeTableColumn(col)
    }
    // … existing setEntries / applyModelSnapshot calls
}
```

- [ ] **Step 8.6: Build + commit**

```bash
(cd apps && xcodegen generate)
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
  -configuration Debug -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
git add apps/Sources/Services/SettingsStore.swift \
        apps/Sources/Views/Settings/CairnSettingsView.swift \
        apps/Sources/App/AppModel.swift \
        apps/Sources/CairnApp.swift \
        apps/Sources/ContentView.swift \
        apps/Sources/Views/FileList/FileListView.swift
git commit -m "feat(settings): add ⌘, Settings scene with 4 panes

General (start folder / tab restore), Appearance (font size + theme
placeholder), Files (default sort + hidden + git column), Advanced
(index cache path, inert rebuild button). Backed by SettingsStore on
UserDefaults, wired through AppModel. Git column visibility now
honours settings.showGitColumn at runtime."
```

---

## Task 9: Glass theme — second pass (bluer, more translucent)

Screenshot feedback: current result reads as muted grey, not the intended "glass blue." Move farther along the blue axis, raise the sidebar tint a notch, and lean on `.hudWindow` material for the window body so the apparent translucency is higher.

**Files:**
- Modify: `apps/Sources/Theme/CairnTheme.swift`
- Modify: `apps/Sources/Views/Sidebar/SidebarView.swift`

- [ ] **Step 9.1: Refresh token values**

Replace the `static let glass = CairnTheme(...)` block with:

```swift
static let glass = CairnTheme(
    id: "glass",
    displayName: "Glass (Blue)",
    windowMaterial: .hudWindow,
    // Clearly blue, more saturated, higher brightness so the tint
    // actually reads as a colour rather than grey.
    sidebarTint: Color(hue: 0.60, saturation: 0.42, brightness: 0.45, opacity: 0.55),
    panelTint:   Color(hue: 0.60, saturation: 0.30, brightness: 0.42, opacity: 0.20),
    text:          Color(white: 0.97),
    textSecondary: Color(white: 0.78),
    textTertiary:  Color(white: 0.56),
    accent:        Color(red: 0.10, green: 0.55, blue: 1.00),
    accentMuted:   Color(red: 0.10, green: 0.55, blue: 1.00, opacity: 0.30),
    selectionFg:   .white,
    cornerRadius: 8,
    rowHeight: 26,
    sidebarRowHeight: 24,
    panelPadding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12),
    bodyFont:   .system(size: 12),
    monoFont:   .system(size: 11, design: .monospaced),
    headerFont: .system(size: 10, weight: .semibold),
    layout: .threePane
)
```

- [ ] **Step 9.2: Sidebar gradient with a more visible top highlight**

In `apps/Sources/Views/Sidebar/SidebarView.swift`, replace the `.background { ZStack { ... } .ignoresSafeArea() }` with:

```swift
.background {
    ZStack {
        VisualEffectBlur(material: .sidebar)
        LinearGradient(
            colors: [
                theme.sidebarTint.opacity(0.70),
                theme.sidebarTint.opacity(0.35)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    .ignoresSafeArea()
}
```

- [ ] **Step 9.3: Build + eyeball**

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
  -configuration Debug -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
open apps/build/Debug/Cairn.app
```

Controller verifies: sidebar has a visible blue wash, selection pill reads clearly blue, window body shows desktop vibrancy.

- [ ] **Step 9.4: Commit**

```bash
git add apps/Sources/Theme/CairnTheme.swift \
        apps/Sources/Views/Sidebar/SidebarView.swift
git commit -m "style(theme): lean glass further into blue + translucency

Previous pass read muted-grey in the user's desktop lighting. Bump
sidebar tint saturation 0.18→0.42 / brightness 0.22→0.45, panel tint
0.22→0.30, raise sidebar gradient opacity 0.55/0.30 → 0.70/0.35,
switch windowMaterial to .hudWindow, and pick a punchier accent blue."
```

---

## Task 10: IndexStore in-memory cache (search perf)

**Context:** `store.list_all()` in `cairn-index/src/store.rs` iterates the full redb table on every fuzzy query. For a 10k-file workspace that's a ~ms-range full scan repeated per keystroke; we want fuzzy to complete in sub-ms.

Strategy: cache `Vec<IndexedFile>` in a `RwLock` guarded by a generation counter that `insert`/`remove` bump. Reads compare counters; on mismatch, rebuild from redb once. No per-query redb hit in steady state.

**Files:**
- Modify: `crates/cairn-index/src/store.rs`
- Create: `crates/cairn-index/tests/store_cache.rs`

- [ ] **Step 10.1: Inspect existing `IndexStore`**

Read `crates/cairn-index/src/store.rs` first and identify:
- The struct holding the redb handle.
- The existing `list_all()` (or equivalent) signature.
- Every `insert` / `remove` / mutation path that would invalidate the cache.

The task below is written against a common shape; adapt names to match the file.

- [ ] **Step 10.2: Add cache state**

On `IndexStore`:

```rust
use std::sync::RwLock;

pub struct IndexStore {
    // … existing fields (db, tables, etc.)
    cache: RwLock<Option<CachedList>>,
    gen:   std::sync::atomic::AtomicU64,
}

struct CachedList {
    gen: u64,
    files: Vec<IndexedFile>,
}
```

Initialise `cache: RwLock::new(None)` and `gen: AtomicU64::new(0)` in every `IndexStore` constructor.

- [ ] **Step 10.3: Bump gen on every mutation**

At the top of each mutator (`insert`, `remove`, `walk_into`, any batch ingest), increment the counter:

```rust
self.gen.fetch_add(1, std::sync::atomic::Ordering::AcqRel);
```

The cached copy stays valid until the counter disagrees.

- [ ] **Step 10.4: Cached `list_all`**

Replace (or rename) the existing `list_all` with:

```rust
pub fn list_all(&self) -> Vec<IndexedFile> {
    let current_gen = self.gen.load(std::sync::atomic::Ordering::Acquire);

    // Fast path: cache hit.
    if let Some(c) = self.cache.read().ok().and_then(|g| g.clone()) {
        if c.gen == current_gen {
            return c.files;
        }
    }

    // Slow path: rebuild.
    let files = self.list_all_from_db();
    if let Ok(mut slot) = self.cache.write() {
        *slot = Some(CachedList { gen: current_gen, files: files.clone() });
    }
    files
}

fn list_all_from_db(&self) -> Vec<IndexedFile> {
    // …original body of the previous list_all lives here…
}
```

If `CachedList` can't be `Clone` because `IndexedFile` isn't, the cache can hold `Arc<Vec<IndexedFile>>` instead — callers receive `Arc::clone(&files)`. Prefer `Clone` if `IndexedFile` already derives it; otherwise use `Arc`.

- [ ] **Step 10.5: Write the Rust cache test**

Create `crates/cairn-index/tests/store_cache.rs`:

```rust
use cairn_index::store::*; // adjust module path to whatever's public

#[test]
fn list_all_cache_hits_on_repeat_calls() {
    // Arrange a store with 3 entries.
    let tmp = tempfile::tempdir().unwrap();
    let store = IndexStore::open(tmp.path()).unwrap();
    // TODO adapt to actual insert API:
    store.insert(IndexedFile::new("a.txt", "/x/a.txt"));
    store.insert(IndexedFile::new("b.txt", "/x/b.txt"));
    store.insert(IndexedFile::new("c.txt", "/x/c.txt"));

    let first = store.list_all();
    let second = store.list_all();
    assert_eq!(first.len(), 3);
    assert_eq!(first, second);
}

#[test]
fn list_all_cache_invalidates_on_insert() {
    let tmp = tempfile::tempdir().unwrap();
    let store = IndexStore::open(tmp.path()).unwrap();
    store.insert(IndexedFile::new("a.txt", "/x/a.txt"));
    let first = store.list_all();

    store.insert(IndexedFile::new("b.txt", "/x/b.txt"));
    let second = store.list_all();

    assert_eq!(first.len(), 1);
    assert_eq!(second.len(), 2);
}
```

If `IndexedFile::new` / `IndexStore::open` / `IndexStore::insert` don't exist with those exact names, adapt to the real API — but keep the test assertions (cache hit ≡ equal; mutation ≡ invalidation).

- [ ] **Step 10.6: Run Rust tests**

```bash
cargo test -p cairn-index
```

Expected: two new tests pass, no regressions in cairn-index.

- [ ] **Step 10.7: Commit**

```bash
git add crates/cairn-index/src/store.rs crates/cairn-index/tests/store_cache.rs
git commit -m "perf(index): cache list_all() between mutations

Fuzzy palette queries hit list_all() per keystroke; each call was a
redb full-table scan. Wrap the list in an RwLock-guarded cache keyed
off an AtomicU64 generation counter bumped by insert / remove / walk,
so steady-state queries read from memory and rebuild lazily only
after a real mutation."
```

---

## Self-Review Notes

- **Spec coverage:** 9 user-reported items + 1 emergent (⌘⇧. reload) → 10 tasks. Task 1 = tab cross-contamination (H). Task 2 = ⌘⇧. reload (new). Task 3 = hidden opacity (C). Task 4 = ⌘K removal (A). Task 5 = right inspector (B). Task 6 = tab bar (F). Task 7 = palette (G). Task 8 = Settings (D). Task 9 = glass 2차 (E). Task 10 = search perf (I). All covered.
- **Placeholder scan:** Every step contains actual code or exact commands. The two "adapt to actual API" notes (Task 10 IndexStore names, Task 3 row style) have clear guardrails: read the file first, follow the existing pattern.
- **Type consistency:** `updateBindings(folder: FolderModel, onActivate:, onAddToPinned:, isPinnedCheck:, onSelectionChanged:)` — matches the init signature. `SettingsStore.StartFolder` enum values `.lastUsed` / `.home` used in both init and `bootstrapInitialURL`.
- **Risk callouts:**
  - Task 1 assumes `FolderModel` uses reference identity `!==` correctly; if someone later makes FolderModel a struct, the guard breaks silently. Add a comment.
  - Task 5's `NavigationSplitViewVisibility` behaviour on macOS 14 is: when the user drags the detail pane closed manually, the binding updates. We don't handle that separately; our button just toggles between `.all` and `.doubleColumn`.
  - Task 10's cache holds a snapshot; callers expecting the returned `Vec` to reflect real-time changes must call `list_all()` again. Document this at the method.
- **Skipped items, explicit:** Fuzzy-mode fallback (Task 7) is substring-only. True nucleo scoring lives in the Rust side; replicating it in Swift isn't worth the maintenance burden for the edge case of IndexService being nil.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-22-cairn-phase1-ux-pass.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, two-stage review, fast iteration.

**2. Inline Execution** — executing-plans with checkpoints.

Which approach?
