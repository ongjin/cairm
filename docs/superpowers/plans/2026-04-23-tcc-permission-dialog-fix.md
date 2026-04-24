# TCC Permission Dialog Fix Implementation Plan

> **For Codex executor:** Each task is self-contained with exact file paths and code. Follow task order. Build/test after each task before moving on. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop macOS from repeatedly prompting for Downloads/Desktop/Documents access when the user clicks the sidebar auto-favorites.

**Architecture:** Three-pronged fix — (1) grant Downloads via App Sandbox entitlement so TCC never asks, (2) add Info.plist usage descriptions so user-selected prompts persist correctly across launches, (3) route sidebar auto-favorite taps through BookmarkStore so Desktop/Documents/Applications get a security-scoped bookmark registered on first use and silently reused afterwards.

**Tech Stack:** Swift / SwiftUI / AppKit, macOS App Sandbox, security-scoped bookmarks, xcodegen (`project.yml`), `apps/Sources/Cairn.entitlements`, `apps/Sources/Info.plist`.

**Reference files (read first):**
- `apps/Sources/Cairn.entitlements` — current entitlements (user-selected only).
- `apps/Sources/Info.plist` — missing usage descriptions.
- `apps/Sources/Views/Sidebar/SidebarView.swift:18-41` — auto-favorites array + tap wiring.
- `apps/Sources/Views/Sidebar/SidebarAutoFavoriteRow.swift` — auto-favorite row view.
- `apps/Sources/App/Tab.swift:113-168` — `navigate(to: BookmarkEntry)` vs `navigate(to: URL)`.
- `apps/Sources/Services/BookmarkStore.swift` — registration, resolve, startAccessing.
- `apps/Sources/App/AppModel.swift:96-121` — existing `reopenFolder` NSOpenPanel + `registerOpenedFolder`.
- `apps/project.yml:22-42` — how entitlements/Info.plist are wired via xcodegen.

---

## File Structure

- **Modify:** `apps/Sources/Cairn.entitlements` — add Downloads entitlement.
- **Modify:** `apps/Sources/Info.plist` — add TCC usage description keys.
- **Modify:** `apps/Sources/Views/Sidebar/SidebarView.swift` — route auto-favorite taps through a new helper that auto-bookmarks on first use.
- **Modify:** `apps/Sources/App/AppModel.swift` — add `openAutoFavorite(url:)` helper.
- **Create:** `apps/CairnTests/AutoFavoriteBookmarkTests.swift` — unit tests.
- **No changes:** `Tab.swift` existing navigate flow stays intact.

---

## Task 1: Add Downloads entitlement

**Files:**
- Modify: `apps/Sources/Cairn.entitlements`

Downloads has its own App Sandbox entitlement (`com.apple.security.files.downloads.read-write`) that auto-grants access without a TCC prompt — this alone kills the most common dialog in the screenshot.

- [ ] **Step 1: Add the entitlement key**

Replace the body of `apps/Sources/Cairn.entitlements` with:

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
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Rebuild project and verify**

Run:
```bash
cd apps && xcodegen generate && cd ..
./scripts/build-rust.sh && xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Debug build -quiet
```
Expected: build succeeds (no signing errors).

- [ ] **Step 3: Manual smoke test**

1. Launch the app.
2. Click "Downloads" in the sidebar.
3. Expected: folder opens immediately, no TCC dialog.
4. Quit, relaunch, click Downloads again — still no dialog.

If a dialog still appears: you may have a stale TCC entry from prior runs. Clear with `tccutil reset SystemPolicyDownloadsFolder com.ongjin.Cairn` (or the actual bundle id) then retry.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/Cairn.entitlements
git commit -m "fix(sandbox): grant Downloads folder entitlement to stop TCC prompt"
```

---

## Task 2: Add Info.plist usage descriptions

**Files:**
- Modify: `apps/Sources/Info.plist`

When the user grants access via NSOpenPanel (Desktop/Documents/Applications path, handled in Task 3), macOS caches the grant *only* if the app declares a usage description string for that folder class. Missing keys cause the grant to re-prompt on next launch. Also required for App Store review if we ever sandbox-distribute.

- [ ] **Step 1: Add the three usage keys before `</dict>`**

Edit `apps/Sources/Info.plist`. Insert these lines immediately before the closing `</dict>` tag (line 27):

```xml
	<key>NSDownloadsFolderUsageDescription</key>
	<string>Cairn shows files in your Downloads folder so you can browse and move them.</string>
	<key>NSDesktopFolderUsageDescription</key>
	<string>Cairn shows files on your Desktop so you can browse and move them.</string>
	<key>NSDocumentsFolderUsageDescription</key>
	<string>Cairn shows files in your Documents folder so you can browse and move them.</string>
```

Final file should have 30 lines including these additions.

- [ ] **Step 2: Rebuild and verify**

Run:
```bash
cd apps && xcodegen generate && cd ..
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Debug build -quiet
```
Expected: build succeeds.

- [ ] **Step 3: Verify the built plist contains the keys**

Run (adjust path if DerivedData differs):
```bash
/usr/libexec/PlistBuddy -c "Print :NSDownloadsFolderUsageDescription" apps/build/Build/Products/Debug/Cairn.app/Contents/Info.plist
```
Expected: prints the string from Step 1.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/Info.plist
git commit -m "fix(sandbox): add NSDownloads/Desktop/Documents folder usage descriptions"
```

---

## Task 3: Auto-bookmark helper in AppModel

**Files:**
- Modify: `apps/Sources/App/AppModel.swift`
- Test: `apps/CairnTests/AutoFavoriteBookmarkTests.swift` (create)

When the user clicks Desktop/Documents/Applications/Home in the sidebar, we check if there's an existing scoped bookmark for that URL. If yes, reuse it (no TCC prompt). If no, show NSOpenPanel pre-targeted at that URL; when the user confirms, register a scoped bookmark and navigate via that bookmark.

- [ ] **Step 1: Write the failing test**

Create `apps/CairnTests/AutoFavoriteBookmarkTests.swift`:

```swift
import XCTest
@testable import Cairn

@MainActor
final class AutoFavoriteBookmarkTests: XCTestCase {
    private var tempDir: URL!
    private var store: BookmarkStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = BookmarkStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_existingBookmark_returnedWithoutPrompt() throws {
        let target = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
        let entry = try store.register(target, kind: .pinned)

        let found = AppModel.lookupExistingBookmark(for: target, in: store)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, entry.id)
    }

    func test_noBookmark_returnsNil() {
        let target = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
        let found = AppModel.lookupExistingBookmark(for: target, in: store)
        XCTAssertNil(found)
    }

    func test_pathStandardization_matchesSymlinkedPrivateTmp() throws {
        // /tmp and /private/tmp both standardize to /private/tmp — confirm the
        // lookup doesn't care which one the caller used.
        let raw = URL(fileURLWithPath: "/tmp")
        let entry = try store.register(raw, kind: .pinned)
        let found = AppModel.lookupExistingBookmark(for: raw, in: store)
        XCTAssertEqual(found?.id, entry.id)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn -only-testing:CairnTests/AutoFavoriteBookmarkTests 2>&1 | tail -20
```
Expected: compile error — `lookupExistingBookmark(for:in:)` is not defined on `AppModel`.

- [ ] **Step 3: Add the lookup helper to AppModel**

Open `apps/Sources/App/AppModel.swift`. Inside the `AppModel` class body, find the `// MARK: - Bookmark helpers` section (around line 112) and append this static helper after `registerOpenedFolder`:

```swift
    // MARK: - Auto-favorite bookmark routing

    /// Return the first pinned or recent entry whose standardized path matches
    /// `url`'s standardized path. Used by sidebar auto-favorites (Home /
    /// Applications / Desktop / Documents / Downloads) to reuse an existing
    /// scoped bookmark instead of re-prompting the user via NSOpenPanel.
    static func lookupExistingBookmark(for url: URL, in store: BookmarkStore) -> BookmarkEntry? {
        let std = url.standardizedFileURL.path
        if let p = store.pinned.first(where: { $0.lastKnownPath == std }) { return p }
        if let r = store.recent.first(where: { $0.lastKnownPath == std }) { return r }
        return nil
    }

    /// Sidebar auto-favorite tap handler. If we already have a scoped
    /// bookmark, navigate via it (no prompt). Otherwise show an NSOpenPanel
    /// pre-targeted at `url`; on confirm, register a scoped bookmark and
    /// navigate via it.
    ///
    /// Downloads does NOT need this path because the
    /// `files.downloads.read-write` entitlement auto-grants access. Applications
    /// is world-readable and also doesn't strictly need it, but routing it
    /// through the same helper keeps the sidebar code uniform.
    @MainActor
    func openAutoFavorite(url: URL, in tab: Tab) {
        if let existing = Self.lookupExistingBookmark(for: url, in: bookmarks) {
            tab.navigate(to: existing)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.message = "Grant Cairn access to \(url.lastPathComponent)"
        panel.prompt = "Grant Access"
        panel.begin { [weak self] response in
            guard response == .OK, let picked = panel.url, let self else { return }
            Task { @MainActor in
                guard let entry = try? self.bookmarks.register(picked, kind: .recent) else {
                    tab.navigate(to: picked)  // graceful fallback: raw URL
                    return
                }
                tab.navigate(to: entry)
            }
        }
    }
```

- [ ] **Step 4: Run tests and verify they pass**

Run:
```bash
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn -only-testing:CairnTests/AutoFavoriteBookmarkTests 2>&1 | tail -20
```
Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/App/AppModel.swift apps/CairnTests/AutoFavoriteBookmarkTests.swift
git commit -m "feat(bookmarks): add auto-favorite bookmark lookup + NSOpenPanel helper"
```

---

## Task 4: Wire sidebar auto-favorites through the helper

**Files:**
- Modify: `apps/Sources/Views/Sidebar/SidebarView.swift`

Replace the four `activeScene.activeTab?.navigate(to: <URL>)` calls for Applications/Desktop/Documents/Downloads/Home with the new `app.openAutoFavorite(url:in:)` entry point.

- [ ] **Step 1: Update the auto-favorite tap handler**

In `apps/Sources/Views/Sidebar/SidebarView.swift` replace the Favorites `ForEach` body (currently line 31–39):

```swift
                    ForEach(autoFavorites, id: \.url) { fav in
                        SidebarAutoFavoriteRow(
                            icon: fav.icon,
                            label: fav.label,
                            url: fav.url,
                            isSelected: isCurrent(fav.url),
                            onActivate: { activeScene.activeTab?.navigate(to: fav.url) }
                        )
                    }
```

with:

```swift
                    ForEach(autoFavorites, id: \.url) { fav in
                        SidebarAutoFavoriteRow(
                            icon: fav.icon,
                            label: fav.label,
                            url: fav.url,
                            isSelected: isCurrent(fav.url),
                            onActivate: {
                                guard let tab = activeScene.activeTab else { return }
                                app.openAutoFavorite(url: fav.url, in: tab)
                            }
                        )
                    }
```

- [ ] **Step 2: Update the Home row (line 84-90)**

Replace:

```swift
                    SidebarAutoFavoriteRow(
                        icon: "house",
                        label: NSUserName(),
                        url: home,
                        isSelected: isCurrent(home),
                        onActivate: { activeScene.activeTab?.navigate(to: home) }
                    )
```

with:

```swift
                    SidebarAutoFavoriteRow(
                        icon: "house",
                        label: NSUserName(),
                        url: home,
                        isSelected: isCurrent(home),
                        onActivate: {
                            guard let tab = activeScene.activeTab else { return }
                            app.openAutoFavorite(url: home, in: tab)
                        }
                    )
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Debug build -quiet
```
Expected: build succeeds.

- [ ] **Step 4: Manual smoke test (the critical one)**

1. Clear any stale TCC entries: `tccutil reset All com.ongjin.Cairn` (adjust bundle id from `project.yml`).
2. Launch the app.
3. Click "Documents" in sidebar. Expected: NSOpenPanel appears prompting for access to `~/Documents` (pre-selected), user clicks "Grant Access".
4. Click "Desktop". Expected: NSOpenPanel appears pre-targeted at `~/Desktop`; grant.
5. Click "Downloads". Expected: folder opens immediately, no panel (entitlement from Task 1 grants this).
6. Quit and relaunch.
7. Click Documents, Desktop, Downloads in sequence. Expected: all three open immediately, no prompts — bookmarks resolve silently.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Views/Sidebar/SidebarView.swift
git commit -m "fix(sidebar): route auto-favorite taps through BookmarkStore to stop repeat TCC prompts"
```

---

## Task 5 (optional): Cleanup and documentation

**Files:**
- Modify: `apps/Sources/App/AppModel.swift` (doc comment only)

Note that `Tab.navigate(to: URL)` at `Tab.swift:166` is still used by Locations items and breadcrumb parent navigation, which is correct — those paths don't need a bookmark because they come from an already-scoped parent walk or a volume mount. Only auto-favorites needed the new helper.

- [ ] **Step 1: Add a clarifying comment to `Tab.navigate(to: URL)`**

In `apps/Sources/App/Tab.swift`, update the doc comment above `navigate(to url: URL)` (currently lines 163-165) to:

```swift
    /// Navigate to an arbitrary URL that we don't (yet) have a bookmark for.
    /// Drops any current scope. Used by breadcrumb parent segments and
    /// Locations items (volume roots, Trash, Network) — callers that KNOW
    /// the URL may lie outside the user-selected scope should prefer
    /// `AppModel.openAutoFavorite(url:in:)` which prompts on first use and
    /// reuses the registered bookmark afterwards.
```

- [ ] **Step 2: Commit**

```bash
git add apps/Sources/App/Tab.swift
git commit -m "docs(tab): clarify navigate(to:URL) vs openAutoFavorite divergence"
```

---

## Self-review checklist

- [ ] Downloads entitlement added in Task 1.
- [ ] Three usage description keys in Info.plist in Task 2.
- [ ] `lookupExistingBookmark(for:in:)` static helper + `openAutoFavorite(url:in:)` instance helper in Task 3.
- [ ] All five auto-favorite tap handlers (Applications, Desktop, Documents, Downloads, Home) route through `openAutoFavorite` in Task 4.
- [ ] Manual relaunch test confirms no repeat dialogs.
- [ ] Locations/breadcrumb code paths unchanged (still use raw `navigate(to: URL)`).

## Known limitations (out of scope for this plan)

- **Full Finder parity with sandbox:** `/Applications`, `/Users`, `/Volumes`, arbitrary paths typed into the address bar still work only when covered by user-selected scope. A complete fix requires unsandboxed distribution (Developer ID signing, notarization). Track separately.
- **Stale bookmark re-prompt UI:** `BookmarkStore.resolve` returns nil on stale, `Tab.navigate(to: entry)` returns silently (Tab.swift:117-120). User sees nothing happen. Add a toast + re-prompt on a follow-up plan.
