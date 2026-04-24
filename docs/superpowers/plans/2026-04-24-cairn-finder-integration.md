# Finder Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three entry points for opening paths in Cairn from outside the app: `cairn://` URL scheme, a CLI wrapper (`cairn open <path>`), and a macOS Services menu item ("Open in Cairn") that appears in Finder's right-click > Services.

**Architecture:** The URL scheme is the canonical entry point — everything else funnels through it. A tiny `CairnURLRouter` parses the URL, asks `AppModel` to open a new tab (local path or SSH host+path), and surfaces errors via the existing connect-sheet flow for unknown SSH aliases. The CLI is a Bash one-liner that `open`s a `cairn://` URL, installed to `/usr/local/bin/cairn` via a Makefile target. The Services menu item is registered via `NSApplication.servicesProvider` + `NSUpdateDynamicServices()` — no separate target, no FinderSync XPC.

**Tech Stack:** Swift 5.9, `URLComponents`, `NSApplication`, `NSUpdateDynamicServices`, existing `AppModel` + `SshConfigService`. Optional: Swift Package CLI target for a binary version later.

**Scope boundary:** No FinderSync extension in v1 (that needs a separate Xcode target, entitlements, and a ~1 week sandbox fight). Services menu + URL scheme + CLI cover 90% of use cases. No deeplink to a specific *file* — only folders — in v1 (file-open would double as "edit in place", which belongs to its own plan).

---

## File Structure

**Create:**
- `apps/Sources/Services/CairnURLRouter.swift` — URL parsing + dispatch to `AppModel`.
- `apps/Sources/Services/CairnServicesProvider.swift` — `NSServicesProvider` methods (`openInCairn(_:userData:error:)`).
- `apps/CairnTests/CairnURLRouterTests.swift`
- `cli/cairn` — shell script, installed to `/usr/local/bin/cairn`.
- `docs/USAGE.md` — user-facing install instructions for the CLI + Services menu.

**Modify:**
- `apps/project.yml` — add `CFBundleURLTypes` (cairn scheme) + `NSServices` (menu entry).
- `apps/Sources/CairnApp.swift` — `.handlesExternalEvents` + `.onOpenURL` hooking into the router; register `NSApp.servicesProvider = CairnServicesProvider.shared` on launch.
- `Makefile` — `install-cli` target that `cp`s `cli/cairn` to `/usr/local/bin/cairn`.

---

## Task 1: URL scheme registration in Info.plist

**Files:**
- Modify: `apps/project.yml`

- [ ] **Step 1: Add CFBundleURLTypes under `info.properties`**

```yaml
info:
  path: Sources/Info.plist
  properties:
    ...
    CFBundleURLTypes:
      - CFBundleURLName: com.ongjin.Cairn.open
        CFBundleURLSchemes: [cairn]
```

- [ ] **Step 2: Regen + build**

Run: `cd apps && xcodegen generate && cd .. && make swift 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Verify the scheme registered**

Run: `plutil -p build/DerivedData/Build/Products/Debug/Cairn.app/Contents/Info.plist | grep -A4 CFBundleURLTypes`
Expected output contains `"CFBundleURLSchemes" => ["cairn"]`.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(finder): register cairn:// URL scheme"
```

---

## Task 2: CairnURLRouter — parsing

**Files:**
- Create: `apps/Sources/Services/CairnURLRouter.swift`
- Test: `apps/CairnTests/CairnURLRouterTests.swift`

- [ ] **Step 1: Failing tests**

```swift
// apps/CairnTests/CairnURLRouterTests.swift
import XCTest
@testable import Cairn

final class CairnURLRouterTests: XCTestCase {
    func test_parse_localOpenURL() throws {
        let req = try CairnURLRouter.parse(URL(string: "cairn://open?path=/Users/me/work")!)
        switch req {
        case .openLocal(let url):
            XCTAssertEqual(url.path, "/Users/me/work")
        default:
            XCTFail("wrong case")
        }
    }

    func test_parse_remoteOpenURL() throws {
        let req = try CairnURLRouter.parse(URL(string: "cairn://remote?host=prod&path=/var/log")!)
        switch req {
        case .openRemote(let alias, let path):
            XCTAssertEqual(alias, "prod")
            XCTAssertEqual(path, "/var/log")
        default:
            XCTFail("wrong case")
        }
    }

    func test_parse_unknownHostReturnsMalformed() {
        XCTAssertThrowsError(try CairnURLRouter.parse(URL(string: "cairn://bogus?x=1")!))
    }

    func test_parse_missingPathOnOpenThrows() {
        XCTAssertThrowsError(try CairnURLRouter.parse(URL(string: "cairn://open")!))
    }

    func test_parse_percentEncodedPathDecoded() throws {
        let req = try CairnURLRouter.parse(URL(string: "cairn://open?path=/tmp/a%20b")!)
        if case .openLocal(let url) = req { XCTAssertEqual(url.path, "/tmp/a b") }
    }
}
```

- [ ] **Step 2: Verify fail**

Run: `make test 2>&1 | grep CairnURLRouter`

- [ ] **Step 3: Implement**

```swift
// apps/Sources/Services/CairnURLRouter.swift
import Foundation

enum CairnOpenRequest: Equatable {
    case openLocal(URL)
    case openRemote(alias: String, path: String)
}

enum CairnURLError: Error, LocalizedError {
    case malformed(String)
    var errorDescription: String? {
        if case .malformed(let m) = self { return "cairn URL: \(m)" }
        return nil
    }
}

enum CairnURLRouter {
    /// Parses a cairn:// URL into a CairnOpenRequest. Supported shapes:
    ///   cairn://open?path=/abs/path
    ///   cairn://remote?host=<ssh_config alias>&path=/abs/path
    static func parse(_ url: URL) throws -> CairnOpenRequest {
        guard url.scheme == "cairn" else {
            throw CairnURLError.malformed("not a cairn URL: \(url)")
        }
        let host = url.host ?? ""
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = comps?.queryItems ?? []

        switch host {
        case "open":
            guard let path = queryItems.first(where: { $0.name == "path" })?.value, !path.isEmpty else {
                throw CairnURLError.malformed("missing path")
            }
            return .openLocal(URL(fileURLWithPath: path))
        case "remote":
            guard let alias = queryItems.first(where: { $0.name == "host" })?.value, !alias.isEmpty else {
                throw CairnURLError.malformed("missing host")
            }
            guard let path = queryItems.first(where: { $0.name == "path" })?.value, !path.isEmpty else {
                throw CairnURLError.malformed("missing path")
            }
            return .openRemote(alias: alias, path: path)
        default:
            throw CairnURLError.malformed("unknown action '\(host)'")
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/CairnURLRouter.swift apps/CairnTests/CairnURLRouterTests.swift
git commit -m "feat(finder): URL router + parsing tests"
```

---

## Task 3: CairnURLRouter — dispatch to AppModel

**Files:**
- Modify: `apps/Sources/Services/CairnURLRouter.swift`
- Test: `apps/CairnTests/CairnURLRouterTests.swift`

- [ ] **Step 1: Failing integration test**

```swift
@MainActor
func test_dispatch_openLocal_opensTabInActivePane() async {
    let app = AppModel()
    let scene = WindowSceneModel(engine: app.engine, bookmarks: app.bookmarks, initialURL: FileManager.default.temporaryDirectory)
    let countBefore = scene.tabs.count
    CairnURLRouter.dispatch(.openLocal(FileManager.default.temporaryDirectory), in: app, activeScene: scene)
    XCTAssertEqual(scene.tabs.count, countBefore + 1)
}
```

- [ ] **Step 2: Verify fail**

- [ ] **Step 3: Implement dispatch**

```swift
extension CairnURLRouter {
    @MainActor
    static func dispatch(_ request: CairnOpenRequest, in app: AppModel, activeScene scene: WindowSceneModel) {
        switch request {
        case .openLocal(let url):
            scene.newTab(initialURL: url)
        case .openRemote(let alias, let path):
            // Re-use the sidebar's silent-connect flow. If the alias isn't in
            // ssh_config we surface the Connect sheet prefilled with it.
            guard app.sshConfig.configuredHosts.contains(alias) else {
                let model = ConnectSheetModel()
                model.server = alias
                scene.connectSheetModel = model
                return
            }
            let placeholder = scene.newEstablishingTab(alias: alias)
            Task { @MainActor in
                do {
                    let target = try await app.ssh.connect(hostAlias: alias, overrides: ConnectSpecOverrides())
                    let provider = SshFileSystemProvider(pool: app.ssh, target: target, supportsServerSideCopy: false)
                    let initial = FSPath(provider: .ssh(target), path: path)
                    placeholder.upgradeToRemote(path: initial, provider: provider)
                    await placeholder.folder.load(initial, via: provider)
                    placeholder.connectionPhase = .connected
                } catch {
                    scene.closeTab(placeholder.id)
                    let model = ConnectSheetModel()
                    model.server = alias
                    model.error = ErrorMessage.userFacing(error)
                    scene.connectSheetModel = model
                }
            }
        }
    }
}
```

(`WindowSceneModel.newTab(initialURL:)` is expected to exist; grep it — if not, add a trivial wrapper that calls the existing `Tab(engine:bookmarks:initialURL:)` and appends to `tabs`.)

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(finder): router dispatches requests to active scene"
```

---

## Task 4: onOpenURL wiring in CairnApp

**Files:**
- Modify: `apps/Sources/CairnApp.swift`

- [ ] **Step 1: Find the `WindowGroup { ContentView() ... }` body and attach `.onOpenURL`**

```swift
WindowGroup {
    ContentView()
        .environment(app)
        ...
        .onOpenURL { url in
            guard let scene = app.activeScene else { return }
            do {
                let req = try CairnURLRouter.parse(url)
                Task { @MainActor in
                    CairnURLRouter.dispatch(req, in: app, activeScene: scene)
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
}
```

`app.activeScene` — if no such property exists, track it via `register(scene:)` sightings. Simplest: keep last-registered as the "active" one.

- [ ] **Step 2: Smoke test from terminal**

Run: `make run && sleep 2 && open "cairn://open?path=/Applications"`
Expected: a new tab appears in the running Cairn window pointing at `/Applications`.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(finder): onOpenURL → route to active scene"
```

---

## Task 5: CLI wrapper `cairn`

**Files:**
- Create: `cli/cairn`
- Modify: `Makefile`

- [ ] **Step 1: Shell script**

```bash
#!/usr/bin/env bash
# Open a path in Cairn. Usage:
#   cairn [open] <path>
#   cairn remote <host-alias> <remote-path>

set -euo pipefail

die() { echo "$*" >&2; exit 1; }

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

cmd="${1:-}"
case "$cmd" in
  "" )
    die "usage: cairn [open] <path> | cairn remote <host> <path>"
    ;;
  remote )
    host="${2:-}" path="${3:-}"
    [ -n "$host" ] && [ -n "$path" ] || die "usage: cairn remote <host> <path>"
    open "cairn://remote?host=$(urlencode "$host")&path=$(urlencode "$path")"
    ;;
  open )
    path="${2:-}"
    [ -n "$path" ] || die "usage: cairn open <path>"
    open "cairn://open?path=$(urlencode "$(cd "$path" >/dev/null 2>&1 && pwd || echo "$path")")"
    ;;
  * )
    # Allow the common form: cairn <path>
    path="$cmd"
    open "cairn://open?path=$(urlencode "$(cd "$path" >/dev/null 2>&1 && pwd || echo "$path")")"
    ;;
esac
```

- [ ] **Step 2: `chmod +x` + install target**

In `Makefile`, add:

```makefile
install-cli: ## Install the `cairn` CLI to /usr/local/bin (sudo may be required).
	@install -m 0755 cli/cairn /usr/local/bin/cairn
	@echo "installed: /usr/local/bin/cairn"

uninstall-cli:
	@rm -f /usr/local/bin/cairn
	@echo "removed: /usr/local/bin/cairn"
```

And:

```bash
chmod +x cli/cairn
```

- [ ] **Step 3: Manual test**

Run: `./cli/cairn open ~/Downloads`
Expected: Cairn opens a new tab on ~/Downloads.

Run: `./cli/cairn ~/Downloads`
Expected: same.

Run: `./cli/cairn remote prod /var/log` (with `prod` alias configured in `~/.ssh/config`)
Expected: new remote tab.

- [ ] **Step 4: Commit**

```bash
git add cli/cairn Makefile
git commit -m "feat(finder): cairn CLI wrapper + make install-cli target"
```

---

## Task 6: Services menu "Open in Cairn"

**Files:**
- Modify: `apps/project.yml` (register NSServices)
- Create: `apps/Sources/Services/CairnServicesProvider.swift`
- Modify: `apps/Sources/CairnApp.swift`

- [ ] **Step 1: Declare the service in Info.plist**

Add under `info.properties`:

```yaml
NSServices:
  - NSMenuItem:
      default: "Open in Cairn"
    NSMessage: openInCairn
    NSPortName: Cairn
    NSSendTypes: [NSFilenamesPboardType, public.file-url]
    NSUserData: ""
```

- [ ] **Step 2: Provider class**

```swift
// apps/Sources/Services/CairnServicesProvider.swift
import AppKit

/// Installed as the app's `NSServicesProvider`. AppKit dispatches
/// `openInCairn(_:userData:error:)` when the user picks "Open in Cairn"
/// from Finder's Services submenu.
@MainActor
final class CairnServicesProvider: NSObject {
    static let shared = CairnServicesProvider()
    weak var app: AppModel?

    @objc func openInCairn(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls: [URL]
        if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls = fileURLs
        } else if let names = pboard.propertyList(forType: .fileURL) as? [String] {
            urls = names.compactMap { URL(string: $0) }
        } else {
            error.pointee = "No file URLs on pasteboard" as NSString
            return
        }
        guard let app = app, let scene = app.activeScene else {
            error.pointee = "Cairn is not ready" as NSString
            return
        }
        for url in urls {
            CairnURLRouter.dispatch(.openLocal(url), in: app, activeScene: scene)
        }
    }
}
```

- [ ] **Step 3: Register on launch**

In `CairnApp.swift`'s `init` or an `.onAppear` on the main WindowGroup:

```swift
NSApp.servicesProvider = CairnServicesProvider.shared
CairnServicesProvider.shared.app = app
NSUpdateDynamicServices()
```

- [ ] **Step 4: Smoke test**

1. `make run`
2. `killall pbs; /System/Library/CoreServices/pbs -update` (refreshes Services menu)
3. In Finder, right-click a folder → Services → expect "Open in Cairn"
4. Click it → expect Cairn to open a tab on that folder

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(finder): NSServices 'Open in Cairn' for Finder right-click"
```

---

## Task 7: USAGE doc for end users

**Files:**
- Create: `docs/USAGE.md`

- [ ] **Step 1: Minimal usage doc**

```markdown
# Opening paths in Cairn from outside the app

Cairn listens on three entry points:

## 1. URL scheme (`cairn://`)

```
cairn://open?path=/Users/you/work
cairn://remote?host=prod&path=/var/log
```

Register happens automatically on first launch. Any macOS app that can open a URL can launch Cairn.

## 2. `cairn` CLI

Install once:

```
make install-cli      # writes /usr/local/bin/cairn
```

Then:

```
cairn ~/work                 # shorthand: open local
cairn open /tmp              # explicit form
cairn remote prod /var/log   # open SSH alias from ~/.ssh/config
```

## 3. Finder > Services > "Open in Cairn"

The service is registered on first launch. If it doesn't appear in Finder's right-click Services submenu:

```
/System/Library/CoreServices/pbs -update
killall Finder
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/USAGE.md
git commit -m "docs(finder): USAGE.md covering URL scheme, CLI, Services menu"
```

---

## Task 8: Smoke tests for each entry point

**Files:**
- Modify: `apps/CairnTests/CairnURLRouterTests.swift` (add dispatch tests)
- Create: `apps/CairnTests/CairnServicesProviderTests.swift`

- [ ] **Step 1: Services provider test**

```swift
@MainActor
final class CairnServicesProviderTests: XCTestCase {
    func test_openInCairn_routesFilePasteboardToNewTab() {
        let pb = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        let url = FileManager.default.temporaryDirectory
        pb.declareTypes([.fileURL], owner: nil)
        pb.writeObjects([url as NSURL])

        let app = AppModel()
        let scene = WindowSceneModel(engine: app.engine, bookmarks: app.bookmarks, initialURL: url)
        CairnServicesProvider.shared.app = app

        var err: NSString = ""
        let countBefore = scene.tabs.count
        // Point `app.activeScene` at this scene for the duration of the call.
        app.register(scene: scene)
        CairnServicesProvider.shared.openInCairn(pb, userData: "", error: &err)
        XCTAssertEqual(err, "")
        XCTAssertEqual(scene.tabs.count, countBefore + 1)
    }
}
```

- [ ] **Step 2: Run tests, expect pass**

- [ ] **Step 3: Commit**

```bash
git commit -am "test(finder): pasteboard → dispatch smoke test"
```

---

## Task 9: Bootstrap Services menu on first launch

**Files:**
- Modify: `apps/Sources/CairnApp.swift`

- [ ] **Step 1: Trigger pbs refresh once per install**

```swift
private func refreshServicesIfNeeded() {
    let defaults = UserDefaults.standard
    let key = "Cairn.ServicesRegisteredAtPath"
    let current = Bundle.main.bundleURL.path
    if defaults.string(forKey: key) != current {
        NSUpdateDynamicServices()
        defaults.set(current, forKey: key)
    }
}
```

Call from the same place you set `NSApp.servicesProvider`.

- [ ] **Step 2: Commit**

```bash
git commit -am "feat(finder): auto-refresh Services menu when app path changes"
```

---

## Self-Review

**Spec coverage**
- ✅ URL scheme → Task 1, 2, 3, 4.
- ✅ CLI → Task 5.
- ✅ Finder right-click → Task 6, 9.

**Placeholder scan**
- `WindowSceneModel.newTab(initialURL:)` assumed to exist — executor must grep + add trivial wrapper if missing.
- `AppModel.activeScene` referenced — if the accessor doesn't exist, expose one that returns the most recently registered scene (existing `sceneRefs` list).
- `ConnectSheetModel`, `ConnectSpecOverrides`, `ErrorMessage.userFacing` — used per the existing sidebar silent-connect flow (`SidebarView.swift:231-259`); executor copies the pattern verbatim.

**Type consistency**
- `CairnOpenRequest`, `CairnURLRouter.parse/dispatch`, `CairnServicesProvider.openInCairn` names stable across tasks.
- All URL query keys (`path`, `host`) match between URL scheme spec, CLI, and router parsing.
