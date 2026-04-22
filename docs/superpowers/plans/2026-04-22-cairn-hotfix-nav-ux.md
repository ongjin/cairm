# Cairn Hotfix — Navigation + UX Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 5 post-M1.8 regressions: CI toolchain break, blocking sidebar navigation, slow parent-folder moves, home-relative breadcrumb display, and a glass-theme refresh.

**Architecture:** Four independent tasks. Task A is a pure config bump. Task B moves the main-thread blocking libgit2 + tantivy open calls off-main via `Task.detached`, with a URL-match guard so stale task results don't overwrite the active tab's services. Task C transforms path components to show `~`. Task D tightens theme tokens and adds a subtle vibrancy layer — no structural view changes.

**Tech Stack:** Rust 1.88 toolchain, Swift 5.10+ / SwiftUI, `@Observable`, `NSVisualEffectView`, swift-bridge FFI to `cairn-index` + `cairn-git`.

---

## File Structure

- `rust-toolchain.toml` — bump channel from `1.85.0` → `1.88.0`. No other toolchain changes.
- `apps/Sources/App/Tab.swift` — add async service-rebuild with cancellation/URL guard.
- `apps/Sources/Views/BreadcrumbBar.swift` — render `~` for the home prefix.
- `apps/Sources/Views/BreadcrumbBar.swift` tests (new) — `apps/CairnTests/BreadcrumbBarTests.swift`.
- `apps/Sources/Theme/CairnTheme.swift` — refreshed glass tokens (brighter, softer).
- `apps/Sources/Views/Sidebar/SidebarView.swift` — thinner separator, selection pill polish.
- `apps/Sources/Views/VisualEffectBlur.swift` — no change; just used with new materials.

---

## Task A: Bump rust-toolchain

**Files:**
- Modify: `rust-toolchain.toml`

- [ ] **Step A1: Replace channel**

```toml
[toolchain]
channel = "1.88.0"
components = ["rustfmt", "clippy"]
targets = ["aarch64-apple-darwin", "x86_64-apple-darwin"]
```

- [ ] **Step A2: Verify local build**

Run: `cargo check --workspace`
Expected: compiles with rustc 1.88 — no rustc-version errors from `home`, `icu_*`, `icu_normalizer_data`, `icu_properties_data`.

If rustup hasn't fetched 1.88 yet, it'll install automatically; `cargo check` blocks until done.

- [ ] **Step A3: Commit**

```bash
git add rust-toolchain.toml
git commit -m "ci: bump rust toolchain to 1.88.0

deps home 0.5.12 / icu_* 2.2.0 require rustc ≥ 1.86–1.88; 1.85 was
rejecting the workspace build on CI."
```

---

## Task B: Async Tab services (fix sidebar-click hang and slow parent navigation)

**Root cause:** `Tab.rebuildServices(for:)` runs synchronously on the main thread on every `navigate(...)`:
  1. `IndexService(root:)` invokes `ffi_index_open` — synchronous tantivy open; slow for large folders (esp. `~`).
  2. `GitService(root:)` invokes `refresh()` — synchronous libgit2 status scan.
The main run-loop blocks until both return, so the UI appears frozen; `onChange(of: tab?.currentFolder)` can't even fire to trigger `folder.load`.

**Fix:** perform both inits on a detached task, set results back on `@MainActor` only if the tab still points at the same URL (cancellation not enough — a newer `navigate` may have already pushed onto history).

**Files:**
- Modify: `apps/Sources/App/Tab.swift`

- [ ] **Step B1: Add state to track in-flight rebuild**

Replace the existing `rebuildServices(for:)` call sites and body in `apps/Sources/App/Tab.swift`.

Add a new stored property on `Tab` (near `var history = NavigationHistory()`):

```swift
/// In-flight detached task that opens IndexService + GitService. Cancelled
/// on a newer navigation so stale results never overwrite the current tab
/// state.
private var servicesTask: Task<Void, Never>?
```

- [ ] **Step B2: Rewrite `rebuildServices` to run off-main**

Replace the existing `private func rebuildServices(for url: URL)` with:

```swift
/// Rebuilds per-folder services. IndexService and GitService both make
/// synchronous FFI calls (tantivy open / libgit2 scan) that can take
/// seconds on a large root — running them off the main thread keeps the
/// UI responsive during navigation.
///
/// Cancels any previous in-flight rebuild and guards against stale results
/// by checking `currentFolder` equals the URL we opened before committing.
private func rebuildServices(for url: URL) {
    servicesTask?.cancel()
    index = nil
    git = nil

    let target = url.standardizedFileURL
    servicesTask = Task.detached { [weak self] in
        let idx = IndexService(root: url)
        let gitSvc = GitService(root: url)
        if Task.isCancelled { return }
        await MainActor.run {
            guard let self else { return }
            guard self.currentFolder?.standardizedFileURL.path == target.path else {
                return
            }
            self.index = idx
            self.git = gitSvc
        }
    }
}
```

- [ ] **Step B3: Cancel on deinit**

Extend the existing `deinit` on `Tab` so the detached task is cancelled if the tab goes away mid-rebuild:

```swift
deinit {
    servicesTask?.cancel()
    if let entry = currentEntry { bookmarks.stopAccessing(entry) }
}
```

- [ ] **Step B4: Build the app**

```bash
cd /Users/cyj/workspace/personal/cairn
./scripts/build-rust.sh && \
  (cd apps && xcodegen generate) && \
  xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
    -configuration Debug -destination "platform=macOS" \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step B5: Manual verification**

Launch the app. Click through sidebar entries: `Desktop → Documents → Downloads → Applications → $HOME`. After each click, the file list should start loading within ~100ms (no multi-second UI freeze). The git branch footer may briefly disappear then repopulate — that's expected since services rebuild in the background.

Then hit `⌘↑` repeatedly to walk up to `/`. Each parent move should feel instant.

- [ ] **Step B6: Commit**

```bash
git add apps/Sources/App/Tab.swift
git commit -m "fix(tab): rebuild services off-main to unfreeze navigation

Tab.rebuildServices called IndexService.init (tantivy open) and
GitService.init -> refresh() (libgit2 status) synchronously on the main
thread. On large roots (esp. \$HOME) this blocked the run-loop for
seconds, making sidebar clicks and ⌘↑ feel like infinite loading.

Move both inits onto a detached Task, guard the main-actor commit with
a currentFolder URL match so a stale rebuild can't overwrite a newer
navigation, and cancel on deinit."
```

---

## Task C: Home-relative breadcrumb

**Files:**
- Modify: `apps/Sources/Views/BreadcrumbBar.swift`
- Create: `apps/CairnTests/BreadcrumbBarTests.swift`

- [ ] **Step C1: Write failing test**

Create `apps/CairnTests/BreadcrumbBarTests.swift`:

```swift
import XCTest
@testable import Cairn

final class BreadcrumbBarTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func test_segments_insideHome_collapsesToTilde() {
        let url = home.appendingPathComponent("Documents/Projects")
        let segs = BreadcrumbBar.segments(for: url, home: home)
        XCTAssertEqual(segs.map(\.label), ["~", "Documents", "Projects"])
        XCTAssertEqual(segs.first?.url, home)
    }

    func test_segments_atHomeRoot_showsOnlyTilde() {
        let segs = BreadcrumbBar.segments(for: home, home: home)
        XCTAssertEqual(segs.map(\.label), ["~"])
        XCTAssertEqual(segs.last?.url, home)
    }

    func test_segments_outsideHome_showsComputerRoot() {
        let url = URL(fileURLWithPath: "/Applications/Utilities")
        let segs = BreadcrumbBar.segments(for: url, home: home)
        XCTAssertEqual(segs.first?.label, BreadcrumbBar.computerName)
        XCTAssertEqual(segs.map(\.label).suffix(2), ["Applications", "Utilities"])
    }
}
```

- [ ] **Step C2: Run test — should fail**

Build + run the test target. Since `segments(for:home:)` doesn't exist yet and the current method is `private`, compilation fails.

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn test \
  -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Expected: compile failure — `No such member 'segments(for:home:)'`.

- [ ] **Step C3: Update BreadcrumbBar to expose the helper and handle home**

Replace `apps/Sources/Views/BreadcrumbBar.swift` contents with:

```swift
import SwiftUI

/// Path segments for the current folder, rendered as clickable buttons.
/// Collapses the user's home prefix to "~" so `~/Documents` shows as
/// `~ › Documents` instead of `Macintosh › Users › cyj › Documents`.
struct BreadcrumbBar: View {
    let tab: Tab?

    /// Cached once — `Host.current().localizedName` is a configd IPC round-trip.
    static let computerName: String = Host.current().localizedName ?? "Computer"

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        if let tab, let current = tab.currentFolder {
            let segs = Self.segments(for: current, home: Self.home)
            HStack(spacing: 2) {
                ForEach(Array(segs.enumerated()), id: \.offset) { pair in
                    let (i, seg) = pair
                    Button(seg.label) { tab.navigate(to: seg.url) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(i == segs.count - 1 ? Color.primary : Color.secondary)
                    if i < segs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    /// Visible for tests. Produces the rendered (label, url) tuples.
    /// Inside `$HOME`: leading segment is `~` pointing at `$HOME`.
    /// Elsewhere: leading segment is the computer name pointing at `/`.
    static func segments(for url: URL, home: URL) -> [(label: String, url: URL)] {
        let std = url.standardizedFileURL
        let homeStd = home.standardizedFileURL

        if std.path == homeStd.path {
            return [("~", homeStd)]
        }

        let homeComponents = homeStd.pathComponents
        let urlComponents = std.pathComponents
        let insideHome =
            urlComponents.count > homeComponents.count &&
            Array(urlComponents.prefix(homeComponents.count)) == homeComponents

        if insideHome {
            var out: [(String, URL)] = [("~", homeStd)]
            var accum = homeStd
            for c in urlComponents.dropFirst(homeComponents.count) {
                accum = accum.appendingPathComponent(c)
                out.append((c, accum))
            }
            return out
        }

        var out: [(String, URL)] = [(computerName, URL(fileURLWithPath: "/"))]
        var accum = URL(fileURLWithPath: "/")
        for (i, c) in urlComponents.enumerated() where i > 0 {
            accum = accum.appendingPathComponent(c)
            out.append((c, accum))
        }
        return out
    }
}
```

- [ ] **Step C4: Run tests — should pass**

```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn test \
  -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Expected: all three `BreadcrumbBarTests` pass.

- [ ] **Step C5: Commit**

```bash
git add apps/Sources/Views/BreadcrumbBar.swift apps/CairnTests/BreadcrumbBarTests.swift
git commit -m "feat(breadcrumb): render home-relative path with ~

Paths inside \$HOME now show '~ › Documents › …' instead of the full
/Macintosh/Users/<name>/Documents chain. Paths outside home keep the
computer-root segment. Covered by BreadcrumbBarTests."
```

---

## Task D: Glass design polish

**Scope:** tighten the existing `.glass` theme. Not a new theme system. Changes are confined to `CairnTheme.swift` token values and a couple of view overlays. If a subjective judgment call comes up mid-task, prefer restraint over ornamentation — this is a Finder replacement, not a showcase.

**Files:**
- Modify: `apps/Sources/Theme/CairnTheme.swift`
- Modify: `apps/Sources/Views/Sidebar/SidebarView.swift`
- Modify: `apps/Sources/Views/Sidebar/SidebarItemRow.swift`
- Modify: `apps/Sources/ContentView.swift`

- [ ] **Step D1: Rework glass tokens**

Replace the `static let glass = CairnTheme(...)` block in `apps/Sources/Theme/CairnTheme.swift` with:

```swift
static let glass = CairnTheme(
    id: "glass",
    displayName: "Glass (Blue)",
    windowMaterial: .underWindowBackground,
    // Softer blue wash — brighter base + lower opacity so the
    // underlying desktop vibrancy reads through more cleanly.
    sidebarTint: Color(hue: 0.60, saturation: 0.18, brightness: 0.22, opacity: 0.55),
    panelTint:   Color(hue: 0.60, saturation: 0.22, brightness: 0.32, opacity: 0.18),
    text:          Color(white: 0.96),
    textSecondary: Color(white: 0.72),
    textTertiary:  Color(white: 0.50),
    accent:        Color(red: 0.04, green: 0.52, blue: 1.00),
    accentMuted:   Color(red: 0.04, green: 0.52, blue: 1.00, opacity: 0.28),
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

- [ ] **Step D2: Upgrade sidebar background stack**

In `apps/Sources/Views/Sidebar/SidebarView.swift`, replace the `.background { ZStack { ... } }` modifier with a gradient-tinted variant:

```swift
.background {
    ZStack {
        VisualEffectBlur(material: .sidebar)
        LinearGradient(
            colors: [
                theme.sidebarTint.opacity(0.55),
                theme.sidebarTint.opacity(0.30)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    .ignoresSafeArea()
}
```

- [ ] **Step D3: Softer selection in sidebar rows**

Open `apps/Sources/Views/Sidebar/SidebarItemRow.swift`. Replace its body with a version that uses the theme's `accentMuted` + `cornerRadius` for selection, and slightly taller rows:

```swift
import SwiftUI

struct SidebarItemRow: View {
    let icon: String
    let label: String
    let tint: Color?
    let isSelected: Bool

    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(tint ?? Color.secondary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(isSelected ? theme.accentMuted : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step D4: Warmer content-column backdrop**

In `apps/Sources/ContentView.swift`, in `fileList(tab:)`, keep the existing `.background { ZStack { ... } }` structure but swap the material + add the same gradient:

```swift
.background {
    ZStack {
        VisualEffectBlur(material: .headerView)
        LinearGradient(
            colors: [
                theme.panelTint.opacity(0.18),
                theme.panelTint.opacity(0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    .ignoresSafeArea()
}
```

- [ ] **Step D5: Build + eyeball**

```bash
./scripts/build-rust.sh && \
  (cd apps && xcodegen generate) && \
  xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn \
    -configuration Debug -destination "platform=macOS" \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
open apps/build/Debug/Cairn.app
```

Walk through: window background, sidebar tint/gradient, row hover, selection pill radius, file list panel. Sidebar should feel airier; selection pill should have a rounded, low-contrast fill; content column should read as cool rather than muddy.

If any of the above looks worse than before, revert just that step — the four D-steps are independent.

- [ ] **Step D6: Commit**

```bash
git add \
  apps/Sources/Theme/CairnTheme.swift \
  apps/Sources/Views/Sidebar/SidebarView.swift \
  apps/Sources/Views/Sidebar/SidebarItemRow.swift \
  apps/Sources/ContentView.swift
git commit -m "style(theme): refresh glass tokens and panel backgrounds

Brighter sidebar/panel tints at lower opacity let vibrancy read through.
Bumped cornerRadius 6→8 and sidebarRowHeight 22→24 for a less cramped
feel. Selection uses accentMuted pill with continuous radius. Content
column now uses .headerView material and a subtle gradient."
```

---

## Self-Review Notes

- **Spec coverage:** 5 issues → 4 tasks. #5 ↦ A. #1, #4 ↦ B. #2 ↦ C. #3 ↦ D. All covered.
- **Placeholder scan:** Every code step has literal code. Every command has exact invocation. No TBDs.
- **Type consistency:** `BreadcrumbBar.segments(for:home:)` signature identical between test and production. `servicesTask: Task<Void, Never>?` referenced consistently in Tab.swift deinit + new body.
- **Risk callouts:**
  - Task B assumes `IndexService` and `GitService` are both thread-safe to instantiate off-main. Both hit the Rust FFI which is stateless per call — safe. The `@Observable` set on main actor is the only UI mutation.
  - Task D's material swap (`.sidebar` → `.underWindowBackground`) changes vibrancy behavior when the window loses focus. If reviewers dislike the desaturation, step D4's `.headerView` can revert to `.contentBackground`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-22-cairn-hotfix-nav-ux.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
