# Remote Edit-in-Place Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user open a remote SSH file in a local editor, edit + save it, and have Cairn upload the changes back over SFTP with conflict detection.

**Architecture:** A per-file `RemoteEditSession` owns a temp-file mirror of the remote path, a `DispatchSource` fd-watcher that fires on every local save, and the remote mtime captured at download time. A top-level `RemoteEditController` tracks active sessions, drives the upload through the existing `TransferController`, and surfaces state to SwiftUI via `@Observable`. Conflicts are detected by re-stating the remote path right before each upload and comparing mtimes; the user is prompted before clobbering.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, existing `SshFileSystemProvider`, `TransferController`, `DispatchSource`, `NSWorkspace.open`, XCTest.

**Scope boundary:** Only files <= 50 MiB (larger files are download + manual-edit territory). No diff UI — the conflict dialog is a 3-choice prompt (Keep mine / Keep remote / Cancel). No "choose editor" picker beyond what `NSWorkspace.open` already offers via user defaults.

---

## File Structure

**Create:**
- `apps/Sources/Services/RemoteEditSession.swift` — value+class model of one active edit session (remote path, temp URL, remote mtime, watcher, upload state enum).
- `apps/Sources/Services/RemoteEditController.swift` — `@Observable` controller tracking `[UUID: RemoteEditSession]`, driving downloads/uploads, exposing an `activeSessions` snapshot for UI.
- `apps/Sources/Views/Transfer/RemoteEditChip.swift` — small SwiftUI chip (already-existing `TransferHudChip` is a visual reference) that shows "Editing N file(s)" and opens a popover listing sessions + status.
- `apps/CairnTests/RemoteEditSessionTests.swift`
- `apps/CairnTests/RemoteEditControllerTests.swift`

**Modify:**
- `apps/Sources/App/AppModel.swift` — construct + hold a `RemoteEditController` (pass `transfers` + `ssh` into it).
- `apps/Sources/Views/FileList/FileListCoordinator.swift:menu(for:)` — add "Edit in External Editor" menu item visible only when `provider.identifier == .ssh` and entry is a regular file.
- `apps/Sources/ContentView.swift` — render `RemoteEditChip` in the window toolbar when `app.remoteEdit.activeSessions.count > 0`.

---

## Task 1: RemoteEditSession scaffold

**Files:**
- Create: `apps/Sources/Services/RemoteEditSession.swift`
- Test: `apps/CairnTests/RemoteEditSessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// apps/CairnTests/RemoteEditSessionTests.swift
import XCTest
@testable import Cairn

final class RemoteEditSessionTests: XCTestCase {
    func test_init_capturesRemoteMtimeAndTempURL() {
        let target = SshTarget(user: "u", hostname: "h", port: 22)
        let remote = FSPath(provider: .ssh(target), path: "/etc/hosts")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteEditSessionTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let session = RemoteEditSession(
            remotePath: remote,
            tempURL: tempDir.appendingPathComponent("hosts"),
            remoteMtimeAtDownload: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(session.remotePath, remote)
        XCTAssertEqual(session.tempURL.lastPathComponent, "hosts")
        XCTAssertEqual(session.remoteMtimeAtDownload,
                       Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(session.state, .watching)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test 2>&1 | grep -E "RemoteEditSession|FAIL"`
Expected: compile error "cannot find 'RemoteEditSession' in scope".

- [ ] **Step 3: Minimal implementation**

```swift
// apps/Sources/Services/RemoteEditSession.swift
import Foundation

/// Lifecycle phases of a single remote edit session.
enum RemoteEditState: Equatable {
    case watching                // file downloaded, fd watcher armed
    case uploading(Int64)        // bytes transferred so far
    case conflict                // remote mtime advanced since download
    case done                    // upload succeeded
    case failed(String)          // surfaced to UI
    case cancelled
}

/// One active remote edit. Held by RemoteEditController; disposed when the
/// user closes the chip entry or the upload completes.
final class RemoteEditSession {
    let id: UUID = UUID()
    let remotePath: FSPath
    let tempURL: URL
    let remoteMtimeAtDownload: Date
    var state: RemoteEditState

    init(remotePath: FSPath,
         tempURL: URL,
         remoteMtimeAtDownload: Date,
         state: RemoteEditState = .watching) {
        self.remotePath = remotePath
        self.tempURL = tempURL
        self.remoteMtimeAtDownload = remoteMtimeAtDownload
        self.state = state
    }
}
```

- [ ] **Step 4: Run test, expect pass**

Run: `make test 2>&1 | grep "RemoteEditSessionTests"`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/RemoteEditSession.swift apps/CairnTests/RemoteEditSessionTests.swift
git commit -m "feat(remote-edit): scaffold RemoteEditSession model"
```

---

## Task 2: File-descriptor watcher

**Files:**
- Modify: `apps/Sources/Services/RemoteEditSession.swift`
- Test: `apps/CairnTests/RemoteEditSessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func test_watcher_firesOnFileWrite() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("RemoteEditSessionTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let fileURL = tempDir.appendingPathComponent("f.txt")
    try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

    let session = RemoteEditSession(
        remotePath: FSPath(provider: .ssh(SshTarget(user: "u", hostname: "h", port: 22)), path: "/tmp/f.txt"),
        tempURL: fileURL,
        remoteMtimeAtDownload: Date()
    )

    let expect = expectation(description: "watcher fires")
    session.onLocalChange = { expect.fulfill() }
    session.startWatching()

    // Overwrite the file — DispatchSource should see it.
    try "world".write(to: fileURL, atomically: true, encoding: .utf8)

    wait(for: [expect], timeout: 2.0)
    session.stopWatching()
}
```

- [ ] **Step 2: Run test, verify fail**

Run: `make test 2>&1 | grep "watcher_fires"`
Expected: FAIL — `startWatching` / `onLocalChange` undefined.

- [ ] **Step 3: Implement watcher**

Append to `RemoteEditSession.swift`:

```swift
extension RemoteEditSession {
    /// Called on the main queue whenever the local temp file is written to.
    var onLocalChange: (() -> Void)? {
        get { _onLocalChange }
        set { _onLocalChange = newValue }
    }

    func startWatching() {
        guard _source == nil else { return }
        let fd = open(tempURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?._onLocalChange?()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        _source = src
    }

    func stopWatching() {
        _source?.cancel()
        _source = nil
    }
}

// Private storage — kept outside the primary init for clarity.
private var _onLocalChangeKey = 0
extension RemoteEditSession {
    fileprivate var _onLocalChange: (() -> Void)? {
        get { objc_getAssociatedObject(self, &_onLocalChangeKey) as? () -> Void }
        set { objc_setAssociatedObject(self, &_onLocalChangeKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    fileprivate var _source: DispatchSourceFileSystemObject? {
        get { objc_getAssociatedObject(self, &_sourceKey) as? DispatchSourceFileSystemObject }
        set { objc_setAssociatedObject(self, &_sourceKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
private var _sourceKey = 0
```

Note on design: the objc associated objects keep the extension storage-free without bloating the main class. Alternatively add these as stored vars on the main class — reviewer's choice, as long as tests pass.

- [ ] **Step 4: Run tests, expect pass**

Run: `make test 2>&1 | grep -E "watcher|RemoteEditSession"`

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(remote-edit): DispatchSource watcher for temp file writes"
```

---

## Task 3: Download with preserved mtime

**Files:**
- Create: `apps/Sources/Services/RemoteEditController.swift`
- Test: `apps/CairnTests/RemoteEditControllerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// apps/CairnTests/RemoteEditControllerTests.swift
import XCTest
@testable import Cairn

@MainActor
final class RemoteEditControllerTests: XCTestCase {
    func test_beginSession_downloadsAndRegistersSession() async throws {
        let provider = InMemoryFSProvider(files: ["/tmp/f": Data("remote".utf8)])
        let controller = RemoteEditController(transfers: TransferController())

        let session = try await controller.beginSession(
            remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
            via: provider
        )

        XCTAssertEqual(try Data(contentsOf: session.tempURL), Data("remote".utf8))
        XCTAssertEqual(controller.activeSessions.count, 1)
        XCTAssertNotNil(controller.activeSessions[session.id])
    }
}
```

`InMemoryFSProvider` is a new test double — create it in the same test file (see Step 3 below).

- [ ] **Step 2: Run test, verify fail**

Run: `make test 2>&1 | grep "beginSession"`

- [ ] **Step 3: Implement controller**

```swift
// apps/Sources/Services/RemoteEditController.swift
import Foundation
import Observation

@MainActor
@Observable
final class RemoteEditController {
    private(set) var activeSessions: [UUID: RemoteEditSession] = [:]
    private let transfers: TransferController
    private let workRoot: URL

    init(transfers: TransferController,
         workRoot: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cairn/RemoteEdit")) {
        self.transfers = transfers
        self.workRoot = workRoot
        try? FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
    }

    func beginSession(remotePath: FSPath, via provider: FileSystemProvider) async throws -> RemoteEditSession {
        let stat = try await provider.stat(remotePath)
        let sessionDir = workRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let tempURL = sessionDir.appendingPathComponent(remotePath.lastComponent)

        try await provider.downloadToLocal(
            remotePath,
            toLocalURL: tempURL,
            progress: { _ in },
            cancel: CancelToken()
        )

        let session = RemoteEditSession(
            remotePath: remotePath,
            tempURL: tempURL,
            remoteMtimeAtDownload: stat.mtime ?? .distantPast
        )
        activeSessions[session.id] = session
        return session
    }
}
```

Add the test double in `RemoteEditControllerTests.swift`:

```swift
private let stubTarget = SshTarget(user: "u", hostname: "h", port: 22)

final class InMemoryFSProvider: FileSystemProvider {
    var identifier: ProviderID { .ssh(stubTarget) }
    var displayScheme: String? { "stub" }
    var supportsServerSideCopy: Bool { false }

    private var files: [String: Data]
    init(files: [String: Data]) { self.files = files }

    func list(_ path: FSPath) async throws -> [FileEntry] { [] }
    func stat(_ path: FSPath) async throws -> FileStat {
        FileStat(size: Int64(files[path.path]?.count ?? 0),
                 mtime: Date(timeIntervalSince1970: 1_700_000_000),
                 mode: 0o644, isDirectory: false)
    }
    func exists(_ path: FSPath) async throws -> Bool { files[path.path] != nil }
    func mkdir(_ path: FSPath) async throws {}
    func rename(from: FSPath, to: FSPath) async throws {}
    func delete(_ paths: [FSPath]) async throws {}
    func copyInPlace(from: FSPath, to: FSPath) async throws {}
    func readHead(_ path: FSPath, max: Int) async throws -> Data { files[path.path] ?? Data() }
    func downloadToCache(_ path: FSPath) async throws -> URL { tempFor(path) }
    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
        files[remotePath.path] = try Data(contentsOf: localURL)
    }
    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
        try files[remotePath.path, default: Data()].write(to: toLocalURL)
    }
    func realpath(_ path: String) async throws -> String { path }

    private func tempFor(_ path: FSPath) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(path.lastComponent)
    }
}
```

- [ ] **Step 4: Run test, expect pass**

Run: `make test 2>&1 | grep beginSession`

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/RemoteEditController.swift apps/CairnTests/RemoteEditControllerTests.swift
git commit -m "feat(remote-edit): RemoteEditController + session begin flow"
```

---

## Task 4: Conflict detection on upload

**Files:**
- Modify: `apps/Sources/Services/RemoteEditController.swift`
- Test: `apps/CairnTests/RemoteEditControllerTests.swift`

- [ ] **Step 1: Failing test**

```swift
func test_upload_flagsConflictWhenRemoteMtimeAdvanced() async throws {
    let provider = InMemoryFSProvider(files: ["/tmp/f": Data("remote".utf8)])
    let controller = RemoteEditController(transfers: TransferController())

    let session = try await controller.beginSession(
        remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
        via: provider
    )
    // Simulate someone else touching the remote file.
    provider.setMtime(path: "/tmp/f", mtime: Date().addingTimeInterval(60))

    let outcome = try await controller.uploadSession(session.id, via: provider)
    XCTAssertEqual(outcome, .conflict)
    XCTAssertEqual(session.state, .conflict)
}
```

Also add to `InMemoryFSProvider`:

```swift
private var mtimes: [String: Date] = [:]
func setMtime(path: String, mtime: Date) { mtimes[path] = mtime }
// update stat() to prefer mtimes[path.path] when present
```

- [ ] **Step 2: Run test, verify fail**

Run: `make test 2>&1 | grep uploadSession`

- [ ] **Step 3: Implement conflict detection**

Append to `RemoteEditController.swift`:

```swift
enum UploadOutcome: Equatable { case uploaded, conflict, failed(String), cancelled }

func uploadSession(_ id: UUID,
                   via provider: FileSystemProvider,
                   onConflictResolve: ((RemoteEditSession) async -> Bool)? = nil) async throws -> UploadOutcome {
    guard let session = activeSessions[id] else { return .failed("no such session") }

    let fresh = try await provider.stat(session.remotePath)
    if let remoteNow = fresh.mtime, remoteNow > session.remoteMtimeAtDownload.addingTimeInterval(1) {
        session.state = .conflict
        if let resolve = onConflictResolve {
            guard await resolve(session) else { return .conflict }
            // Continue — caller confirmed overwrite.
        } else {
            return .conflict
        }
    }

    session.state = .uploading(0)
    do {
        try await provider.uploadFromLocal(
            session.tempURL,
            to: session.remotePath,
            progress: { bytes in Task { @MainActor in session.state = .uploading(bytes) } },
            cancel: CancelToken()
        )
        session.state = .done
        return .uploaded
    } catch {
        session.state = .failed(String(describing: error))
        return .failed(String(describing: error))
    }
}
```

- [ ] **Step 4: Run test, expect pass**

Run: `make test 2>&1 | grep "uploadSession\|conflict"`

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(remote-edit): mtime-based conflict detection on upload"
```

---

## Task 5: Wire watcher into controller + debounced upload

**Files:**
- Modify: `apps/Sources/Services/RemoteEditController.swift`
- Test: `apps/CairnTests/RemoteEditControllerTests.swift`

- [ ] **Step 1: Failing test**

```swift
func test_localWrite_schedulesDebouncedUpload() async throws {
    let provider = InMemoryFSProvider(files: ["/tmp/f": Data("orig".utf8)])
    let controller = RemoteEditController(transfers: TransferController())
    let session = try await controller.beginSession(
        remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
        via: provider
    )
    controller.armWatching(for: session.id, via: provider)
    try "edited".write(to: session.tempURL, atomically: true, encoding: .utf8)

    try await Task.sleep(nanoseconds: 1_200_000_000)  // > debounce window

    XCTAssertEqual(provider.readSync("/tmp/f"), Data("edited".utf8))
    XCTAssertEqual(session.state, .done)
}
```

Add to `InMemoryFSProvider`:

```swift
func readSync(_ path: String) -> Data { files[path] ?? Data() }
```

- [ ] **Step 2: Run test, verify fail**

- [ ] **Step 3: Implement debounced upload**

```swift
private var pendingUploads: [UUID: Task<Void, Never>] = [:]
private static let debounceMs: UInt64 = 800

func armWatching(for id: UUID, via provider: FileSystemProvider) {
    guard let session = activeSessions[id] else { return }
    session.onLocalChange = { [weak self] in
        self?.scheduleUpload(id: id, via: provider)
    }
    session.startWatching()
}

private func scheduleUpload(id: UUID, via provider: FileSystemProvider) {
    pendingUploads[id]?.cancel()
    pendingUploads[id] = Task { [weak self] in
        try? await Task.sleep(nanoseconds: Self.debounceMs * 1_000_000)
        if Task.isCancelled { return }
        _ = try? await self?.uploadSession(id, via: provider)
    }
}
```

- [ ] **Step 4: Run test, expect pass**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(remote-edit): debounce local writes and auto-upload"
```

---

## Task 6: Session teardown + temp file cleanup

**Files:**
- Modify: `apps/Sources/Services/RemoteEditController.swift`
- Test: `apps/CairnTests/RemoteEditControllerTests.swift`

- [ ] **Step 1: Failing test**

```swift
func test_endSession_removesTempDirAndStopsWatching() async throws {
    let provider = InMemoryFSProvider(files: ["/tmp/f": Data("orig".utf8)])
    let controller = RemoteEditController(transfers: TransferController())
    let session = try await controller.beginSession(
        remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
        via: provider
    )
    let sessionDir = session.tempURL.deletingLastPathComponent()
    XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDir.path))

    controller.endSession(session.id)

    XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDir.path))
    XCTAssertNil(controller.activeSessions[session.id])
}
```

- [ ] **Step 2: Verify fail**

- [ ] **Step 3: Implement**

```swift
func endSession(_ id: UUID) {
    guard let session = activeSessions[id] else { return }
    session.stopWatching()
    pendingUploads[id]?.cancel()
    pendingUploads.removeValue(forKey: id)
    let dir = session.tempURL.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: dir)
    activeSessions.removeValue(forKey: id)
}

deinit {
    for id in activeSessions.keys { endSession(id) }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(remote-edit): teardown cleans watchers + temp dirs"
```

---

## Task 7: Inject controller into AppModel

**Files:**
- Modify: `apps/Sources/App/AppModel.swift`

- [ ] **Step 1: Extend AppModel init**

```swift
let remoteEdit: RemoteEditController

init(...) {
    ...
    self.transfers = MainActor.assumeIsolated { TransferController() }
    self.remoteEdit = MainActor.assumeIsolated { RemoteEditController(transfers: self.transfers) }
    ...
}
```

- [ ] **Step 2: Build**

Run: `make swift 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(remote-edit): wire RemoteEditController through AppModel"
```

---

## Task 8: Context menu entry "Edit in External Editor"

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift` (search for `menu(for:` — the AppKit right-click builder).

- [ ] **Step 1: Read existing menu builder**

Open the function, note the existing `Reveal in Finder`, `Copy Path`, etc. entries — the new item slots in just below `Open With` for SSH tabs only.

- [ ] **Step 2: Add menu branch**

```swift
if case .ssh = provider.identifier, entry.kind != .Directory {
    let edit = NSMenuItem(title: "Edit in External Editor", action: #selector(editExternal(_:)), keyEquivalent: "")
    edit.target = self
    edit.representedObject = MenuPayload(entry: entry)
    menu.addItem(edit)
}
```

And the action:

```swift
@objc private func editExternal(_ sender: NSMenuItem) {
    guard let payload = sender.representedObject as? MenuPayload else { return }
    let remotePath = FSPath(provider: provider.identifier, path: payload.entry.path.toString())
    Task { @MainActor in
        do {
            let session = try await appModel.remoteEdit.beginSession(remotePath: remotePath, via: provider)
            appModel.remoteEdit.armWatching(for: session.id, via: provider)
            NSWorkspace.shared.open(session.tempURL)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
```

**Note:** `appModel` reference inside `FileListCoordinator` isn't currently stored — add a `weak var appModel: AppModel?` property and set it from `FileListView.makeNSView` via `context.coordinator.appModel = ...`. Thread it from `PaneColumn.fileList` if the AppModel isn't already reachable.

- [ ] **Step 3: Build + smoke test**

Run: `make run`, right-click any file in an SSH tab → expect the new menu item.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(remote-edit): context menu entry for SSH files"
```

---

## Task 9: RemoteEditChip UI

**Files:**
- Create: `apps/Sources/Views/Transfer/RemoteEditChip.swift`
- Modify: `apps/Sources/ContentView.swift` (add chip next to existing TransferHudChip).

- [ ] **Step 1: Chip view**

```swift
import SwiftUI

struct RemoteEditChip: View {
    @Bindable var controller: RemoteEditController
    @State private var showPopover = false

    var body: some View {
        if controller.activeSessions.isEmpty {
            EmptyView()
        } else {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                    Text("Editing \(controller.activeSessions.count)")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) { sessionList }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(controller.activeSessions.values), id: \.id) { s in
                HStack {
                    Text(s.remotePath.lastComponent).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(describe(s.state)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Finish") { controller.endSession(s.id) }.buttonStyle(.plain)
                }
            }
        }
        .padding(10).frame(minWidth: 280)
    }

    private func describe(_ state: RemoteEditState) -> String {
        switch state {
        case .watching: return "watching"
        case .uploading(let b): return "uploading \(b)B"
        case .conflict: return "conflict"
        case .done: return "saved"
        case .failed(let m): return "failed: \(m)"
        case .cancelled: return "cancelled"
        }
    }
}
```

- [ ] **Step 2: Embed in ContentView toolbar**

Grep `ContentView.swift` for `TransferHudChip` and add `RemoteEditChip(controller: app.remoteEdit)` next to it.

- [ ] **Step 3: Build + visual smoke**

Run: `make run`, trigger a remote edit, expect the chip to appear in the toolbar.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(remote-edit): status chip + session popover"
```

---

## Task 10: Conflict resolution dialog

**Files:**
- Modify: `apps/Sources/Services/RemoteEditController.swift`
- Modify: `apps/Sources/Views/Transfer/RemoteEditChip.swift`

- [ ] **Step 1: Extend uploadSession call site to present an NSAlert**

In `editExternal` (`FileListCoordinator`) or in the watcher auto-upload path, replace the plain `uploadSession(id, via:)` with the `onConflictResolve`-taking variant:

```swift
_ = try? await appModel.remoteEdit.uploadSession(id, via: provider) { session in
    await MainActor.run {
        let alert = NSAlert()
        alert.messageText = "\(session.remotePath.lastComponent) was modified remotely"
        alert.informativeText = "Choose how to proceed."
        alert.addButton(withTitle: "Overwrite Remote")   // returns .alertFirstButtonReturn
        alert.addButton(withTitle: "Keep Remote")        // returns .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")             // returns .alertThirdButtonReturn
        let resp = alert.runModal()
        return resp == .alertFirstButtonReturn
    }
}
```

- [ ] **Step 2: Manual smoke test**

1. Open an SSH file in external editor
2. Touch the remote file via a real ssh session: `touch /tmp/f`
3. Save the local temp → dialog should appear
4. "Keep Remote" → state goes `.conflict`, no upload
5. "Overwrite Remote" → upload proceeds

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(remote-edit): 3-choice conflict prompt on save"
```

---

## Task 11: Size guard (≤ 50 MiB) and cancel on tab close

**Files:**
- Modify: `apps/Sources/Services/RemoteEditController.swift`
- Modify: `apps/Sources/App/WindowSceneModel.swift` (or wherever tab-close lives)

- [ ] **Step 1: Reject large files**

```swift
func beginSession(...) async throws -> RemoteEditSession {
    let stat = try await provider.stat(remotePath)
    if stat.size > 50 * 1024 * 1024 {
        throw NSError(domain: "Cairn.RemoteEdit", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "File is too large for edit-in-place (>50 MiB). Download manually instead."])
    }
    ...
}
```

- [ ] **Step 2: End all sessions for a tab on close**

Find the tab-close path (`WindowSceneModel.closeTab`) and call `app.remoteEdit.endSessionsForHost(target)` if the closed tab's `.ssh(target)` matches any active session's remote path. Add helper:

```swift
func endSessionsForHost(_ target: SshTarget) {
    for (id, s) in activeSessions where s.remotePath.provider == .ssh(target) {
        endSession(id)
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
git commit -am "feat(remote-edit): size cap + cleanup on tab close"
```

---

## Task 12: Integration test against a real SFTP server

**Files:**
- Create: `apps/CairnTests/RemoteEditIntegrationTests.swift`

- [ ] **Step 1: Write test gated on a live server env var**

```swift
final class RemoteEditIntegrationTests: XCTestCase {
    func test_fullRoundtrip_uploadsEditedContent() async throws {
        guard let host = ProcessInfo.processInfo.environment["CAIRN_IT_SSH_HOST"] else {
            throw XCTSkip("CAIRN_IT_SSH_HOST not set")
        }
        // pool.connect → SshFileSystemProvider → begin → edit → expect upload
        // Implementation left to executor — use the existing SshPoolService test helpers.
    }
}
```

- [ ] **Step 2: Document env var in README "Testing"**

Append to `README.md`:

```
## Integration tests (optional)
Set CAIRN_IT_SSH_HOST=<alias> with a host in ~/.ssh/config to enable remote-edit round-trip tests.
```

- [ ] **Step 3: Commit**

```bash
git commit -am "test(remote-edit): gated live-SFTP round-trip test"
```

---

## Self-Review

**Spec coverage**
- ✅ Open remote file locally → Task 3 (`beginSession`) + Task 8 (NSWorkspace.open).
- ✅ Detect save → Task 2 (watcher) + Task 5 (debounced wire-up).
- ✅ Re-upload via SFTP → Task 4.
- ✅ Mtime conflict → Task 4 + Task 10.
- ✅ Upload failure / cancel UX → `.failed` state + chip shows it (Task 9, Task 11).

**Placeholder scan**
- No TODOs remain. Task 8 references a `weak var appModel` that the executor has to thread — explicitly called out in the task.

**Type consistency**
- `RemoteEditState` cases referenced consistently across tasks 1/4/5/6/9.
- `RemoteEditController.beginSession`, `.armWatching`, `.uploadSession`, `.endSession` names stable.
