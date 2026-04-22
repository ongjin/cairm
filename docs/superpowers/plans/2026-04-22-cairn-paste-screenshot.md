# Cairn Clipboard Paste & Screenshot Save — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Finder-style clipboard behavior to Cairn: ⌘V/⌥⌘V paste files from Finder (copy/move), ⌘C copy Cairn selection to the pasteboard, and ⌘V save clipboard images (e.g., macOS screenshots) as `Untitled.png` in the current folder.

**Architecture:** A new pure-logic module `ClipboardPasteService` owns pasteboard reading, collision-free destination naming, and TIFF→PNG conversion. Paste orchestration lives on `FileListCoordinator` (which already owns undo plumbing and reload triggers). The Edit menu and ⌘C/⌘V/⌥⌘V key equivalents route through the standard Cocoa **responder chain** (`NSResponder.copy(_:)`, `paste(_:)`, and a custom `pasteItemHere(_:)`) — AppKit auto-validates menu items via `validateMenuItem` and auto-grays entries when there's nothing to paste, so we avoid the cross-layer FocusedValue plumbing that the original spec contemplated.

**Tech Stack:** Swift 5, AppKit (`NSTableView`, `NSPasteboard`, `NSBitmapImageRep`, `NSWorkspace`), XCTest, SwiftUI `CommandGroup` for Edit menu.

**Spec:** `docs/superpowers/specs/2026-04-22-cairn-paste-screenshot-design.md`

---

## File Inventory

**Create**

- `apps/Sources/Services/ClipboardPasteService.swift` — pure helpers: `PasteContent`, `PasteOp`, `CollisionRule`, `read(from:)`, `uniqueDestination`, `tiffToPng`, `writeFileURLs`.
- `apps/CairnTests/ClipboardPasteServiceTests.swift` — XCTest unit tests for the service.
- `apps/Sources/App/CairnResponder.swift` — a minimal `@objc` protocol declaring `pasteItemHere(_:)` so both the SwiftUI menu button and the `FileListNSTableView` can reference the same selector.

**Modify**

- `apps/Sources/Views/FileList/FileListNSTableView.swift` — override `copy(_:)`, `paste(_:)`, add `pasteItemHere(_:)`, add `validateMenuItem(_:)`; expose `copyHandler` and `pasteHandler` closures. Leave existing `keyDown` alone; key bindings ride the Edit-menu responder chain.
- `apps/Sources/Views/FileList/FileListView.swift` — wire the two new closures to coordinator methods.
- `apps/Sources/Views/FileList/FileListCoordinator.swift` — add `hasSelection`, `copySelectedToClipboard`, `pasteFromClipboard(operation:)`, undo registrations for copy-paste and image-paste; extend right-click context menu to include "Copy" on row menus and "Paste" / "Paste Item Here" on empty-space menus.
- `apps/Sources/CairnApp.swift` — extend `EditCommands` with Copy / Paste / Paste Item Here buttons that `NSApp.sendAction(...)` onto the responder chain.

---

## Task 1: Create `ClipboardPasteService` skeleton with types

**Files:**
- Create: `apps/Sources/Services/ClipboardPasteService.swift`

- [ ] **Step 1: Create the file with enums and a stub namespace**

```swift
// apps/Sources/Services/ClipboardPasteService.swift
import AppKit

/// Direction of a paste: copy leaves the source intact, move removes it.
/// Used by both the keyboard shortcut dispatch (⌘V vs ⌥⌘V) and the menu.
enum PasteOp {
    case copy
    case move
}

/// What the pasteboard contains, in the priority Cairn cares about. File URLs
/// always win over image data (matches Finder's behavior when a user drags an
/// image out of an app into Finder — Finder pastes the file, not the bytes).
enum PasteContent {
    case files([URL])
    /// Raw bytes ready to write to disk with the given extension.
    case image(data: Data, ext: String)
}

/// Naming policy when the destination already exists.
enum CollisionRule {
    /// Finder's file-copy style: "foo.txt" → "foo copy.txt" → "foo copy 2.txt".
    case appendCopy
    /// Finder's new-folder / screenshot style: "Untitled.png" → "Untitled 2.png".
    case appendNumber
}

/// Pure helpers for moving data between NSPasteboard and the filesystem.
/// No AppKit view state, no main-thread requirements — everything here is safe
/// to unit test in isolation.
enum ClipboardPasteService {
    // Implementations added in later tasks.
    static func read(from pb: NSPasteboard) -> PasteContent? { fatalError("stub") }

    static func uniqueDestination(filename: String,
                                  in dir: URL,
                                  rule: CollisionRule) -> URL { fatalError("stub") }

    static func tiffToPng(_ tiff: Data) -> Data? { fatalError("stub") }

    static func writeFileURLs(_ urls: [URL], to pb: NSPasteboard) { fatalError("stub") }
}
```

- [ ] **Step 2: Regenerate the Xcode project and compile**

Run: `make swift`
Expected: Build succeeds. The stubs `fatalError` on call but nothing calls them yet.

- [ ] **Step 3: Commit**

```bash
git add apps/Sources/Services/ClipboardPasteService.swift
git commit -m "feat(paste): scaffold ClipboardPasteService types"
```

---

## Task 2: `uniqueDestination` (TDD, both collision rules)

**Files:**
- Modify: `apps/Sources/Services/ClipboardPasteService.swift`
- Create: `apps/CairnTests/ClipboardPasteServiceTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// apps/CairnTests/ClipboardPasteServiceTests.swift
import XCTest
@testable import Cairn

final class ClipboardPasteServiceTests: XCTestCase {

    // MARK: - Fixture

    private var tmp: URL!

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-paste-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    private func touch(_ name: String) {
        FileManager.default.createFile(atPath: tmp.appendingPathComponent(name).path,
                                       contents: Data())
    }

    // MARK: - uniqueDestination / appendCopy

    func test_uniqueDestination_appendCopy_noCollisionReturnsOriginal() {
        let url = ClipboardPasteService.uniqueDestination(
            filename: "foo.txt", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "foo.txt")
    }

    func test_uniqueDestination_appendCopy_firstCollision() {
        touch("foo.txt")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "foo.txt", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "foo copy.txt")
    }

    func test_uniqueDestination_appendCopy_secondCollision() {
        touch("foo.txt")
        touch("foo copy.txt")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "foo.txt", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "foo copy 2.txt")
    }

    func test_uniqueDestination_appendCopy_thirdCollision() {
        touch("foo.txt")
        touch("foo copy.txt")
        touch("foo copy 2.txt")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "foo.txt", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "foo copy 3.txt")
    }

    func test_uniqueDestination_appendCopy_dotfile() {
        touch(".gitignore")
        let url = ClipboardPasteService.uniqueDestination(
            filename: ".gitignore", in: tmp, rule: .appendCopy)
        // Leading-dot files have no "extension" in Finder's view.
        XCTAssertEqual(url.lastPathComponent, ".gitignore copy")
    }

    func test_uniqueDestination_appendCopy_compositeExtension() {
        touch("archive.tar.gz")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "archive.tar.gz", in: tmp, rule: .appendCopy)
        // Finder splits on the LAST dot only.
        XCTAssertEqual(url.lastPathComponent, "archive.tar copy.gz")
    }

    func test_uniqueDestination_appendCopy_noExtension() {
        touch("Makefile")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Makefile", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "Makefile copy")
    }

    // MARK: - uniqueDestination / appendNumber

    func test_uniqueDestination_appendNumber_noCollision() {
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.png", in: tmp, rule: .appendNumber)
        XCTAssertEqual(url.lastPathComponent, "Untitled.png")
    }

    func test_uniqueDestination_appendNumber_firstCollision() {
        touch("Untitled.png")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.png", in: tmp, rule: .appendNumber)
        XCTAssertEqual(url.lastPathComponent, "Untitled 2.png")
    }

    func test_uniqueDestination_appendNumber_secondCollision() {
        touch("Untitled.png")
        touch("Untitled 2.png")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.png", in: tmp, rule: .appendNumber)
        XCTAssertEqual(url.lastPathComponent, "Untitled 3.png")
    }

    func test_uniqueDestination_appendNumber_differentExtDoesNotCollide() {
        touch("Untitled.png")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.jpg", in: tmp, rule: .appendNumber)
        XCTAssertEqual(url.lastPathComponent, "Untitled.jpg")
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `make test`
Expected: Build fails at `fatalError("stub")` OR tests fail with `XCTAssertion` failures. Either way, the point is that the test file compiles and the behavior is not yet implemented.

If the build instead fails because `ClipboardPasteServiceTests.swift` isn't part of the test target, regenerate: `cd apps && xcodegen generate` and re-run. The `CairnTests` target's `sources` globbing in `project.yml` should already pick up anything under `apps/CairnTests/`.

- [ ] **Step 3: Implement `uniqueDestination` and `splitName`**

Replace the `uniqueDestination` stub in `ClipboardPasteService.swift` and add the private helper:

```swift
    static func uniqueDestination(filename: String,
                                  in dir: URL,
                                  rule: CollisionRule) -> URL {
        let initial = dir.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: initial.path) {
            return initial
        }
        let (base, ext) = splitName(filename)
        var n = 2
        while true {
            let candidate: String
            switch rule {
            case .appendCopy:
                // n == 2 is the FIRST collision → unsuffixed " copy".
                // n == 3+ → " copy <n-1>" to match Finder ("foo copy", "foo copy 2").
                let suffix = (n == 2) ? "copy" : "copy \(n - 1)"
                candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            case .appendNumber:
                // Straight numbering starting at 2 ("Untitled 2.png").
                candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            }
            let url = dir.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            n += 1
        }
    }

    /// Finder's filename/extension split. Returns extension without the leading dot.
    /// - Dotfiles (leading ".", no more dots): whole name is the base, no extension.
    /// - Composite extensions ("foo.tar.gz"): split on LAST dot only → ("foo.tar", "gz").
    /// - No dot: whole name is base, no extension.
    private static func splitName(_ filename: String) -> (base: String, ext: String) {
        if filename.hasPrefix(".") && !filename.dropFirst().contains(".") {
            return (filename, "")
        }
        if let dotIdx = filename.lastIndex(of: "."), dotIdx != filename.startIndex {
            let base = String(filename[..<dotIdx])
            let ext = String(filename[filename.index(after: dotIdx)...])
            return (base, ext)
        }
        return (filename, "")
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: all `test_uniqueDestination_*` cases pass. `fatalError` stubs for `read`, `tiffToPng`, `writeFileURLs` remain — they're not touched yet.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/ClipboardPasteService.swift apps/CairnTests/ClipboardPasteServiceTests.swift
git commit -m "feat(paste): collision-free destination naming"
```

---

## Task 3: `tiffToPng` (TDD)

**Files:**
- Modify: `apps/Sources/Services/ClipboardPasteService.swift`
- Modify: `apps/CairnTests/ClipboardPasteServiceTests.swift`

- [ ] **Step 1: Write failing test**

Append to `ClipboardPasteServiceTests.swift`:

```swift
    // MARK: - tiffToPng

    func test_tiffToPng_roundtripsThroughNSImage() {
        // 1×1 white pixel as TIFF. NSImage → tiffRepresentation is the simplest way.
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation else {
            return XCTFail("fixture: couldn't produce TIFF")
        }

        let png = ClipboardPasteService.tiffToPng(tiff)
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 0)
        // PNG magic number: 89 50 4E 47 0D 0A 1A 0A
        let expectedMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(png!.prefix(8)), expectedMagic)
    }

    func test_tiffToPng_returnsNilForGarbage() {
        let garbage = Data([0x00, 0x01, 0x02])
        XCTAssertNil(ClipboardPasteService.tiffToPng(garbage))
    }
```

- [ ] **Step 2: Run test and verify failure**

Run: `make test`
Expected: test traps on `fatalError("stub")` inside `tiffToPng`.

- [ ] **Step 3: Implement `tiffToPng`**

Replace the stub:

```swift
    static func tiffToPng(_ tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: all tests green.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/ClipboardPasteService.swift apps/CairnTests/ClipboardPasteServiceTests.swift
git commit -m "feat(paste): TIFF→PNG conversion for clipboard images"
```

---

## Task 4: `read(from:)` pasteboard priority (TDD)

**Files:**
- Modify: `apps/Sources/Services/ClipboardPasteService.swift`
- Modify: `apps/CairnTests/ClipboardPasteServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `ClipboardPasteServiceTests.swift`:

```swift
    // MARK: - read(from:)

    /// Allocates a fresh, uniquely-named pasteboard so tests don't clobber
    /// the user's real clipboard or race with each other.
    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("cairn.test.\(UUID().uuidString)"))
    }

    func test_read_emptyPasteboardReturnsNil() {
        let pb = scratchPasteboard()
        pb.clearContents()
        XCTAssertNil(ClipboardPasteService.read(from: pb))
    }

    func test_read_fileURLsWinOverImage() {
        let pb = scratchPasteboard()
        pb.clearContents()
        // Stage both kinds and assert file URLs take priority.
        let fileURL = tmp.appendingPathComponent("sample.txt")
        touch("sample.txt")
        pb.writeObjects([fileURL as NSURL])
        pb.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)

        guard case .files(let urls) = ClipboardPasteService.read(from: pb) else {
            return XCTFail("expected .files")
        }
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.lastPathComponent, "sample.txt")
    }

    func test_read_pngImageOnly() {
        let pb = scratchPasteboard()
        pb.clearContents()
        let fakePng = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        pb.setData(fakePng, forType: .png)

        guard case .image(let data, let ext) = ClipboardPasteService.read(from: pb) else {
            return XCTFail("expected .image")
        }
        XCTAssertEqual(data, fakePng)
        XCTAssertEqual(ext, "png")
    }

    func test_read_tiffConvertsToPng() {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!

        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)

        guard case .image(let data, let ext) = ClipboardPasteService.read(from: pb) else {
            return XCTFail("expected .image")
        }
        XCTAssertEqual(ext, "png")
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        XCTAssertEqual(Array(data.prefix(4)), pngMagic)
    }

    func test_read_jpegPassthrough() {
        let pb = scratchPasteboard()
        pb.clearContents()
        let fakeJpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        pb.setData(fakeJpeg, forType: jpegType)

        guard case .image(let data, let ext) = ClipboardPasteService.read(from: pb) else {
            return XCTFail("expected .image")
        }
        XCTAssertEqual(data, fakeJpeg)
        XCTAssertEqual(ext, "jpg")
    }
```

- [ ] **Step 2: Run tests and verify failure**

Run: `make test`
Expected: traps on `fatalError("stub")` in `read(from:)`.

- [ ] **Step 3: Implement `read(from:)`**

Replace the stub:

```swift
    static func read(from pb: NSPasteboard) -> PasteContent? {
        // 1. File URLs — Finder's ⌘C stages this; Cairn drag-drop uses it too.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        // 2. PNG — what macOS screencapture puts on the clipboard.
        if let data = pb.data(forType: .png) {
            return .image(data: data, ext: "png")
        }
        // 3. TIFF — "Copy Image" in some browsers. Normalize to PNG so the
        //    saved file is compact and universally recognized.
        if let tiff = pb.data(forType: .tiff),
           let png = tiffToPng(tiff) {
            return .image(data: png, ext: "png")
        }
        // 4. JPEG — some screenshot utilities stage this directly. Passthrough.
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        if let data = pb.data(forType: jpegType) {
            return .image(data: data, ext: "jpg")
        }
        return nil
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: all `test_read_*` cases green.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/ClipboardPasteService.swift apps/CairnTests/ClipboardPasteServiceTests.swift
git commit -m "feat(paste): pasteboard reader with file/PNG/TIFF/JPEG priority"
```

---

## Task 5: `writeFileURLs` (TDD)

**Files:**
- Modify: `apps/Sources/Services/ClipboardPasteService.swift`
- Modify: `apps/CairnTests/ClipboardPasteServiceTests.swift`

- [ ] **Step 1: Write failing test**

Append to tests:

```swift
    // MARK: - writeFileURLs

    func test_writeFileURLs_roundtripsThroughPasteboard() {
        let a = tmp.appendingPathComponent("a.txt")
        let b = tmp.appendingPathComponent("b.txt")
        touch("a.txt"); touch("b.txt")

        let pb = scratchPasteboard()
        ClipboardPasteService.writeFileURLs([a, b], to: pb)

        let readBack = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(readBack?.map { $0.lastPathComponent }, ["a.txt", "b.txt"])
    }
```

- [ ] **Step 2: Run test and verify failure**

Run: `make test`
Expected: traps on `fatalError("stub")`.

- [ ] **Step 3: Implement**

Replace the stub:

```swift
    static func writeFileURLs(_ urls: [URL], to pb: NSPasteboard) {
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Services/ClipboardPasteService.swift apps/CairnTests/ClipboardPasteServiceTests.swift
git commit -m "feat(paste): NSPasteboard writer for Cairn ⌘C"
```

---

## Task 6: Responder protocol + NSTableView overrides

**Files:**
- Create: `apps/Sources/App/CairnResponder.swift`
- Modify: `apps/Sources/Views/FileList/FileListNSTableView.swift`

- [ ] **Step 1: Create the protocol file**

```swift
// apps/Sources/App/CairnResponder.swift
import AppKit

/// Custom responder actions Cairn contributes to the standard Cocoa menu.
/// The protocol exists only so SwiftUI `CommandGroup` buttons and the
/// NSTableView subclass can share one `#selector` reference for the
/// non-standard ⌥⌘V "Paste Item Here" move action. Cocoa's built-in
/// `copy:` / `paste:` are reused unchanged.
@objc protocol CairnResponder: AnyObject {
    @objc func pasteItemHere(_ sender: Any?)
}
```

- [ ] **Step 2: Add closures and responder overrides to `FileListNSTableView`**

At the top of `apps/Sources/Views/FileList/FileListNSTableView.swift`, add two properties next to the existing `deleteHandler`:

```swift
    /// Fired on ⌘C — copy selected rows' URLs to the general pasteboard.
    var copyHandler: (() -> Void)?

    /// Fired on ⌘V (.copy) or ⌥⌘V (.move).
    var pasteHandler: ((PasteOp) -> Void)?
```

Then, below the existing `menu(for:)` method, add responder overrides:

```swift
    // MARK: - Standard Cocoa edit actions

    override func copy(_ sender: Any?) {
        copyHandler?()
    }

    override func paste(_ sender: Any?) {
        pasteHandler?(.copy)
    }

    // Custom selector, declared on CairnResponder. NSMenuItem in the Edit menu
    // uses this selector, and the responder chain finds us because we're the
    // window's first responder when the table is focused.
    @objc func pasteItemHere(_ sender: Any?) {
        pasteHandler?(.move)
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)):
            return !selectedRowIndexes.isEmpty
        case #selector(paste(_:)), #selector(pasteItemHere(_:)):
            return ClipboardPasteService.read(from: .general) != nil
        default:
            return super.validateMenuItem(item)
        }
    }
```

The class does not need to declare conformance to `CairnResponder` — Objective-C message dispatch matches on selector, not static type. The protocol exists solely so the Edit menu button (Task 11) can reference `#selector(CairnResponder.pasteItemHere(_:))` without importing AppKit-subclass types.

- [ ] **Step 3: Build**

Run: `make swift`
Expected: Build succeeds. No runtime wiring yet — `copyHandler` and `pasteHandler` are still nil.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/App/CairnResponder.swift apps/Sources/Views/FileList/FileListNSTableView.swift
git commit -m "feat(paste): table-view responder hooks for copy/paste"
```

---

## Task 7: Coordinator `copySelectedToClipboard` + wiring

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift`
- Modify: `apps/Sources/Views/FileList/FileListView.swift`

- [ ] **Step 1: Add `copySelectedToClipboard` to the Coordinator**

Find the existing drag-and-drop extension marker `// MARK: - Drag & drop (file move)` in `FileListCoordinator.swift`. Immediately before it, add a new MARK section:

```swift
    // MARK: - Clipboard (⌘C / ⌘V / ⌥⌘V)

    /// True when at least one row is selected. Used by NSTableView's
    /// validateMenuItem to gray out "Copy" when nothing's picked.
    var hasSelection: Bool {
        (table?.selectedRowIndexes.isEmpty ?? true) == false
    }

    /// Writes the selected rows' absolute URLs to the general pasteboard as
    /// `.fileURL` items. Finder reads these directly — pasting in Finder
    /// yields real files, not a path string.
    ///
    /// Distinct from the existing "Copy Path" menu item (⌥⌘C), which writes
    /// the path as a plain string for shell-paste workflows.
    func copySelectedToClipboard() {
        guard let table else { return }
        let indexes = table.selectedRowIndexes
        guard !indexes.isEmpty else { NSSound.beep(); return }
        let urls = indexes.compactMap { idx -> URL? in
            guard idx >= 0, idx < lastSnapshot.count else { return nil }
            return URL(fileURLWithPath: lastSnapshot[idx].path.toString())
        }
        guard !urls.isEmpty else { return }
        ClipboardPasteService.writeFileURLs(urls, to: .general)
    }
```

- [ ] **Step 2: Wire the handler in `FileListView.makeNSView`**

In `apps/Sources/Views/FileList/FileListView.swift`, find the existing:

```swift
        table.deleteHandler = { [weak coord = context.coordinator] in
            coord?.deleteSelected()
        }
```

Immediately after it, add:

```swift
        table.copyHandler = { [weak coord = context.coordinator] in
            coord?.copySelectedToClipboard()
        }
```

- [ ] **Step 3: Build and smoke-test**

Run: `make swift`
Expected: Build succeeds.

Then `make run`. In the running app, with a folder open and the file list focused, try ⌘C. Nothing visible should happen yet (no Edit menu button wired), but if you open another app and hit ⌘V… actually, don't test this way — no global shortcut yet dispatches our copy. This step is purely structural. The real end-to-end test comes in Task 11.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/Views/FileList/FileListCoordinator.swift apps/Sources/Views/FileList/FileListView.swift
git commit -m "feat(paste): coordinator copy-to-clipboard"
```

---

## Task 8: Coordinator paste — file copy branch + undo

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift`
- Modify: `apps/Sources/Views/FileList/FileListView.swift`

- [ ] **Step 1: Add `pasteFromClipboard` with copy branch**

Below `copySelectedToClipboard` in the new "Clipboard" section, add:

```swift
    /// Entry point for ⌘V and ⌥⌘V. Reads the general pasteboard, dispatches
    /// on content + operation, and registers undo for anything that lands.
    ///
    /// Currently handles `.files` + `.copy`. `.files` + `.move` and `.image`
    /// branches are added in later tasks.
    func pasteFromClipboard(operation: PasteOp) {
        guard let dir = folder.currentFolder else { NSSound.beep(); return }
        guard FileManager.default.isWritableFile(atPath: dir.path) else {
            showPasteAlert("The current folder isn't writable.")
            return
        }
        guard let content = ClipboardPasteService.read(from: .general) else {
            NSSound.beep(); return
        }
        switch (content, operation) {
        case (.files(let urls), .copy):
            pasteCopy(urls: urls, into: dir)
        default:
            NSSound.beep()  // later tasks fill in .move and .image
        }
    }

    private func pasteCopy(urls: [URL], into dir: URL) {
        var created: [(src: URL, dest: URL)] = []
        for src in urls {
            let dest = ClipboardPasteService.uniqueDestination(
                filename: src.lastPathComponent, in: dir, rule: .appendCopy)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                created.append((src, dest))
            } catch {
                NSSound.beep()
            }
        }
        if !created.isEmpty {
            registerPasteCopyUndo(created)
            onMoved()
        }
    }

    /// Undo for a paste-copy deletes the just-created files (hard delete —
    /// not trash — because they existed for <1s and trashing them creates
    /// noise in `~/.Trash` the user didn't ask for).
    /// Redo re-runs `copyItem` with the same source/destination pairs.
    private func registerPasteCopyUndo(_ pairs: [(src: URL, dest: URL)]) {
        guard let undoManager else { return }
        let onMoved = self.onMoved
        let target = self
        undoManager.registerUndo(withTarget: target) { _ in
            for (_, dest) in pairs {
                try? FileManager.default.removeItem(at: dest)
            }
            onMoved()
            undoManager.registerUndo(withTarget: target) { coord in
                coord.replayPasteCopy(pairs)
            }
        }
        undoManager.setActionName(pairs.count == 1 ? "Paste" : "Paste \(pairs.count) Items")
    }

    private func replayPasteCopy(_ pairs: [(src: URL, dest: URL)]) {
        var done: [(URL, URL)] = []
        for (src, dest) in pairs {
            if (try? FileManager.default.copyItem(at: src, to: dest)) != nil {
                done.append((src, dest))
            }
        }
        if !done.isEmpty {
            registerPasteCopyUndo(done)
            onMoved()
        }
    }

    private func showPasteAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't paste"
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
```

- [ ] **Step 2: Confirm `folder.currentFolder` exists**

Run: `grep -n "currentFolder" apps/Sources/ViewModels/FolderModel.swift apps/Sources/Services/*.swift apps/Sources/App/Tab.swift`
Expected: `FolderModel` (or `Tab`) exposes a `currentFolder: URL?`. If only `Tab` has it, inject the URL into the coordinator another way — see the existing `FileListView` props. Check `FolderModel.swift` first:

```bash
grep -n "var currentFolder\|let currentFolder\|currentURL" apps/Sources/ViewModels/FolderModel.swift
```

If `FolderModel` doesn't have `currentFolder`, add a computed/stored URL there (the drop handler in `FileListCoordinator` already reads `folder` — check how).

Actually, look at the existing `folder` field on the Coordinator (`private weak var folder: FolderModel?` — grep to confirm line number) and read how other methods get the current directory. If the only way is via `folder.entries.first?.path.parentDirectory`, add a proper `currentURL` property to `FolderModel` at the top of the file:

```swift
    /// The directory these entries came from. Set by `load(_:)`.
    private(set) var currentFolder: URL?
```

And in `load(_ url: URL) async`, set `self.currentFolder = url` at the same point the entries snapshot is installed.

- [ ] **Step 3: Wire the handler in `FileListView.makeNSView`**

Immediately after the `copyHandler` wiring from Task 7:

```swift
        table.pasteHandler = { [weak coord = context.coordinator] op in
            coord?.pasteFromClipboard(operation: op)
        }
```

- [ ] **Step 4: Build**

Run: `make swift`
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Views/FileList/FileListCoordinator.swift apps/Sources/Views/FileList/FileListView.swift apps/Sources/ViewModels/FolderModel.swift
git commit -m "feat(paste): file-copy branch with undo"
```

---

## Task 9: Coordinator paste — file move branch

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift`

- [ ] **Step 1: Extend the switch in `pasteFromClipboard`**

Locate the `switch (content, operation)` inside `pasteFromClipboard`. Replace its body with:

```swift
        switch (content, operation) {
        case (.files(let urls), .copy):
            pasteCopy(urls: urls, into: dir)
        case (.files(let urls), .move):
            pasteMove(urls: urls, into: dir)
        default:
            NSSound.beep()  // .image branches handled in Task 10
        }
```

- [ ] **Step 2: Add `pasteMove`**

Below `pasteCopy` add:

```swift
    private func pasteMove(urls: [URL], into dir: URL) {
        var moved: [(URL, URL)] = []
        for src in urls {
            let dest = dir.appendingPathComponent(src.lastPathComponent)
            // Matches existing drag-drop policy: beep + skip on name collision.
            if FileManager.default.fileExists(atPath: dest.path) {
                NSSound.beep(); continue
            }
            // Source == dest (pasting a file inside its own folder) → skip.
            if src.standardizedFileURL.path == dest.standardizedFileURL.path {
                continue
            }
            do {
                try FileManager.default.moveItem(at: src, to: dest)
                moved.append((src, dest))
            } catch {
                NSSound.beep()
            }
        }
        if !moved.isEmpty {
            // registerMoveUndo is the existing drag-drop undo path —
            // it already sets action name "Move" / "Move N Items", which is
            // exactly right for ⌥⌘V too.
            registerMoveUndo(moved)
            onMoved()
        }
    }
```

- [ ] **Step 3: Note about `fileprivate` visibility**

`registerMoveUndo` is currently declared `fileprivate` inside the drag-drop extension at the bottom of `FileListCoordinator.swift`. Because the new clipboard code also lives in the same file, `fileprivate` is fine — no visibility change needed. If the build complains ("not visible here"), widen to `private` on the class level (drop the extension indirection) — do NOT make it `internal`.

- [ ] **Step 4: Build**

Run: `make swift`
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(paste): file-move branch reusing drag-drop undo"
```

---

## Task 10: Coordinator paste — image branch

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift`

- [ ] **Step 1: Handle `.image` in the switch**

Replace the switch body in `pasteFromClipboard` one more time:

```swift
        switch (content, operation) {
        case (.files(let urls), .copy):
            pasteCopy(urls: urls, into: dir)
        case (.files(let urls), .move):
            pasteMove(urls: urls, into: dir)
        case (.image(let data, let ext), _):
            // Operation is ignored for images — clipboard images don't have a
            // source file to move. ⌘V and ⌥⌘V both "paste" the image.
            pasteImage(data: data, ext: ext, into: dir)
        }
```

The compiler now sees all cases as handled; remove the `default: NSSound.beep()` branch.

- [ ] **Step 2: Add `pasteImage`**

Below `pasteMove`:

```swift
    private func pasteImage(data: Data, ext: String, into dir: URL) {
        let dest = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.\(ext)", in: dir, rule: .appendNumber)
        // Off-main write: a retina screenshot PNG is ~10 MB and would hitch
        // scrolling if written synchronously on the main actor.
        let onMoved = self.onMoved
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try data.write(to: dest, options: .atomic)
                await MainActor.run {
                    self?.registerPasteImageUndo(dest: dest, data: data)
                    onMoved()
                }
            } catch {
                await MainActor.run { NSSound.beep() }
            }
        }
    }

    private func registerPasteImageUndo(dest: URL, data: Data) {
        guard let undoManager else { return }
        let onMoved = self.onMoved
        let target = self
        undoManager.registerUndo(withTarget: target) { _ in
            try? FileManager.default.removeItem(at: dest)
            onMoved()
            undoManager.registerUndo(withTarget: target) { coord in
                coord.replayPasteImage(dest: dest, data: data)
            }
        }
        undoManager.setActionName("Paste Screenshot")
    }

    private func replayPasteImage(dest: URL, data: Data) {
        // Find a fresh collision-free name in case the user filled the
        // original slot between undo and redo.
        let dir = dest.deletingLastPathComponent()
        let fresh = ClipboardPasteService.uniqueDestination(
            filename: dest.lastPathComponent, in: dir, rule: .appendNumber)
        if (try? data.write(to: fresh, options: .atomic)) != nil {
            registerPasteImageUndo(dest: fresh, data: data)
            onMoved()
        } else {
            NSSound.beep()
        }
    }
```

- [ ] **Step 3: Build**

Run: `make swift`
Expected: success. If the compiler complains that the switch is now exhaustive but still has a `default`, delete the `default` line.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(paste): image branch (PNG/JPEG) with Untitled naming + undo"
```

---

## Task 11: Context menu entries

**Files:**
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift`

- [ ] **Step 1: Add "Copy" to the row context menu**

Find the existing `@objc private func menuCopyPath(_ sender: NSMenuItem)` method, and the place it's constructed with `let copyPath = NSMenuItem(title: "Copy Path", …)`. Immediately above that construction, add a new "Copy" item (⌘C is the main keystroke; the menu key-equivalent is cosmetic, since AppKit will dispatch through the responder chain either way):

```swift
        let copyItem = NSMenuItem(title: "Copy",
                                  action: #selector(menuCopyEntry(_:)),
                                  keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.target = self
        copyItem.representedObject = MenuPayload(entry: entry)
        menu.addItem(copyItem)
```

Then add the action handler alongside the existing `@objc private func menuCopyPath` (just below it):

```swift
    @objc private func menuCopyEntry(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload else { return }
        let url = URL(fileURLWithPath: payload.entry.path.toString())
        ClipboardPasteService.writeFileURLs([url], to: .general)
    }
```

- [ ] **Step 2: Add Paste items for empty-space right-click**

Find the coordinator's `menu(for event:)` method. It currently builds a row menu only when a row is under the click. When `row < 0` (click lands in empty space) it probably returns nil or a minimal menu — grep to confirm its current shape:

```bash
grep -n "func menu(for" apps/Sources/Views/FileList/FileListCoordinator.swift
```

If `menu(for:)` returns `nil` for empty-space clicks, replace that early-return with an empty-space menu:

```swift
    func menu(for event: NSEvent) -> NSMenu? {
        guard let table else { return nil }
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        if row < 0 {
            return emptySpaceMenu()
        }
        // ... existing row-menu construction continues here
    }

    private func emptySpaceMenu() -> NSMenu? {
        let canPaste = ClipboardPasteService.read(from: .general) != nil
        guard canPaste else { return nil }
        let menu = NSMenu()
        let pasteItem = NSMenuItem(title: "Paste",
                                   action: #selector(NSText.paste(_:)),
                                   keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = [.command]
        menu.addItem(pasteItem)

        // "Paste Item Here" only makes sense when the clipboard has file URLs,
        // not a raw image.
        if case .files = ClipboardPasteService.read(from: .general) {
            let moveItem = NSMenuItem(title: "Paste Item Here",
                                      action: #selector(CairnResponder.pasteItemHere(_:)),
                                      keyEquivalent: "v")
            moveItem.keyEquivalentModifierMask = [.command, .option]
            menu.addItem(moveItem)
        }
        return menu
    }
```

The actions here use `nil` target — AppKit walks the responder chain, finds `FileListNSTableView`'s `paste(_:)` / `pasteItemHere(_:)`, and fires them. This keeps the context menu and the Edit menu sharing one dispatch path.

- [ ] **Step 3: Build and smoke-test**

Run: `make swift && make run`
Expected:
- Right-click a row → "Copy" appears, hitting it puts the URL on the clipboard. Test by pasting into Finder.
- Right-click empty space with something on the clipboard → "Paste" (+ "Paste Item Here" if files) appears and works.
- Right-click empty space with nothing on the clipboard → no menu.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(paste): context-menu Copy / Paste / Paste Item Here"
```

---

## Task 12: Edit menu buttons

**Files:**
- Modify: `apps/Sources/CairnApp.swift`

- [ ] **Step 1: Extend `EditCommands`**

Find the existing `struct EditCommands: Commands` (around line 226). Replace the body of `CommandGroup(replacing: .undoRedo) { … }` to include the three new buttons AFTER the existing Undo/Redo pair:

```swift
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) { undoManager?.undo() }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!(undoManager?.canUndo ?? false))
            Button(redoTitle) { undoManager?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(undoManager?.canRedo ?? false))
        }
        CommandGroup(after: .pasteboard) {
            // Copy / Paste / Paste Item Here route through the responder chain.
            // `NSApp.sendAction(_:to:from:)` with `to: nil` walks first → last
            // responder; FileListNSTableView's overrides (Task 6) pick them up
            // when the table has focus.
            Button("Copy") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("Paste") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: [.command])

            Button("Paste Item Here") {
                NSApp.sendAction(#selector(CairnResponder.pasteItemHere(_:)),
                                 to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
        }
    }
```

Why `#selector(NSText.copy(_:))` instead of `NSResponder.copy(_:)`: Apple's Swift SDK exposes `copy:` / `paste:` on `NSText` but not directly on `NSResponder` because `NSResponder.copy(_:)` would collide with Swift's `copy()` idiom. Any responder with the matching selector still wins, so our `FileListNSTableView.copy(_:)` override is what fires.

- [ ] **Step 2: Build**

Run: `make swift`
Expected: success.

- [ ] **Step 3: Smoke-test end-to-end**

Run: `make run`. Verify each of the following in the live app:

- In Finder, ⌘C a file. Click Cairn's file list (give it focus). ⌘V → file copied into current folder, visible in the row list. ⌘Z → it vanishes.
- Same file still on clipboard. ⌥⌘V → file moved (Finder shows it gone).
- In Cairn, select a row, ⌘C, switch to Finder, ⌘V → real file appears there.
- Take a screenshot with ⌃⌘⇧4 (copies to clipboard). Cairn focused, ⌘V → `Untitled.png` appears. Take another → `Untitled 2.png`. ⌘Z on the second undoes just that one.
- Empty clipboard, ⌘V → Edit menu's Paste is grayed; nothing happens on key press either.

- [ ] **Step 4: Commit**

```bash
git add apps/Sources/CairnApp.swift
git commit -m "feat(paste): Edit menu Copy/Paste/Paste Item Here"
```

---

## Task 13: Manual QA log + final polish

**Files:** (no source changes unless QA surfaces bugs)

- [ ] **Step 1: Run the full test suite**

Run: `make test`
Expected: all tests green, including the new `ClipboardPasteServiceTests`.

- [ ] **Step 2: Execute QA checklist**

Document results for each line below in the PR description (paste this checklist into the PR body, check off as you verify):

- [ ] Finder ⌘C single file → Cairn ⌘V → copy appears
- [ ] Finder ⌘C multi-select → Cairn ⌘V → all copied, single ⌘Z removes all
- [ ] Cairn ⌘C → Finder ⌘V → real files in Finder
- [ ] Cairn ⌘C → Cairn ⌘V same folder → `foo copy.txt`
- [ ] Cairn ⌘C → Cairn ⌘V same folder second time → `foo copy 2.txt`
- [ ] Finder ⌘C → Cairn ⌥⌘V → file moved out of Finder
- [ ] ⌃⌘⇧4 screenshot → Cairn ⌘V → `Untitled.png`
- [ ] Second screenshot paste → `Untitled 2.png`
- [ ] Chrome "Copy Image" (JPEG-backed img) → Cairn ⌘V → `Untitled.png` or `Untitled.jpg`
- [ ] Empty clipboard → Cairn ⌘V → beep, Edit→Paste grayed
- [ ] Right-click empty space with files on clipboard → Paste + Paste Item Here appear
- [ ] Right-click empty space with image on clipboard → Paste only (no Paste Item Here)
- [ ] Right-click empty space with empty clipboard → no menu
- [ ] ⌘⌫ trash still works (regression check — we touched keyDown area indirectly)
- [ ] Drag-drop move still works + undoable (regression check — registerMoveUndo shared)

- [ ] **Step 3: Spec coverage audit**

Open `docs/superpowers/specs/2026-04-22-cairn-paste-screenshot-design.md` and verify each requirement maps to a task above. Any gap → add a follow-up task and finish it before moving on.

- [ ] **Step 4: Final commit (only if QA required fixes)**

If QA surfaced a bug requiring changes, commit them with a descriptive message:
```bash
git add <paths>
git commit -m "fix(paste): <what the bug was>"
```

If QA was clean, skip this step.

---

## Out-of-Scope (do NOT implement in this plan)

- Restoring ⌘⌫-trashed files via ⌘Z (sandbox constraints — descoped).
- Progress UI for very large paste operations.
- Conflict-resolution dialog ("Replace / Keep Both / Skip") — we use deterministic renaming for copy and beep-and-skip for move, same as the existing drag-drop behavior.
- Localization — the app is currently English-only; `"Untitled"`, `"Paste"`, `"Copy"` stay as plain string literals matching `"Copy Path"` / `"Move to Trash"` / etc.
- Multi-image paste in a single ⌘V.
