# Cairn — Clipboard Paste & Screenshot Save (Design)

**Date**: 2026-04-22
**Branch context**: `hotfix/glass-inspector-warp-makefile-2026-04-22` (hotfix scope)
**Scope**: Two user-facing features bundled under one spec because they share the clipboard/paste pipeline.

## 1. Goal & Non-Goals

**Goal**: Make Cairn's file list participate in the macOS clipboard the way Finder does, so:

1. A user who copies a file in Finder (⌘C) can paste it into the Cairn-displayed folder with ⌘V (copy) or ⌥⌘V (move).
2. A user who copies files in Cairn (⌘C) can paste them into Finder or back into another Cairn tab.
3. A user who captures a screenshot to the clipboard (⌃⌘⇧4, or any app that puts image data on the pasteboard) can paste it into the current Cairn folder as a real image file.

**Non-goals**:

- Restoring files from `~/.Trash` via ⌘Z after ⌘⌫ (sandbox-fragile; intentionally descoped this round).
- Pasting rich text or other non-image/non-file pasteboard content.
- Multi-image paste in a single ⌘V (macOS pasteboard conventionally holds one image at a time).
- Paste progress UI or conflict-resolution dialog. Conflicts are handled by deterministic renaming (copy) or beep-and-skip (move), matching the existing drag-drop policy.

## 2. Current State (as of exploration)

- `FileListCoordinator.swift` already registers undo entries for drag-drop moves (`registerMoveUndo`) and ⌘⌫ trash (`registerBatchTrashUndo`). Both hang off `Tab.undoManager`, which the Edit menu reads via `@FocusedValue(\.tabUndoManager)`.
- The existing "Copy Path" context menu item (⌥⌘C) copies the **path string** to the clipboard. It does NOT put `.fileURL` on the pasteboard — so pasting into Finder yields a path literal, not a file. This stays unchanged; we add a new ⌘C that does the `.fileURL` write.
- No `⌘V`, `⌥⌘V`, or image-paste support anywhere. The NSTableView subclass handles ⏎, Space, and ⌘⌫ only.
- App is sandboxed with `user-selected.read-write` and app-scope bookmarks. `trashItem` works because it routes through Powerbox; restoring from Trash does not, which is why undo-delete is out of scope.
- App has no localization — all UI strings are English constants. New strings follow the same convention.

## 3. Architecture

### 3.1 New service: `ClipboardPasteService`

Location: `apps/Sources/Services/ClipboardPasteService.swift`

Pure, Coordinator-independent module containing all paste logic that does not need AppKit view state. This keeps `FileListCoordinator.swift` (already 857 lines) from growing further and gives us a testable boundary.

```swift
enum PasteContent {
    case files([URL])
    case image(data: Data, ext: String)  // ext ∈ {"png", "jpg"}
}

enum PasteOp { case copy, move }

enum CollisionRule { case appendCopy, appendNumber }

struct ClipboardPasteService {
    /// Reads pasteboard with priority: file URLs > PNG > TIFF (converted to PNG) > JPEG.
    /// Returns nil if nothing pasteable.
    static func read(from pb: NSPasteboard) -> PasteContent?

    /// Generates a collision-free destination URL under `dir` for a desired
    /// filename. `appendCopy` → "foo copy.txt", "foo copy 2.txt"; `appendNumber`
    /// → "Untitled.png", "Untitled 2.png". Handles dotted filenames like
    /// ".gitignore" (no extension split) and composite ".tar.gz" (split on
    /// last dot only — matches Finder).
    static func uniqueDestination(named: String,
                                  in dir: URL,
                                  rule: CollisionRule) -> URL

    /// Convert TIFF data to PNG. Returns nil on malformed TIFF.
    static func tiffToPng(_ tiff: Data) -> Data?

    /// Writes `.fileURL` entries to the given pasteboard. Used by ⌘C from Cairn.
    static func writeFileURLs(_ urls: [URL], to pb: NSPasteboard)
}
```

### 3.2 Coordinator entry points

`FileListCoordinator` gains:

```swift
func copySelectedToClipboard()                       // ⌘C
func pasteFromClipboard(operation: PasteOp)          // ⌘V / ⌥⌘V
```

Internally `pasteFromClipboard` calls `ClipboardPasteService.read(...)` and dispatches:

- `.files(urls)` → loop, compute destination with `appendCopy` rule, `copyItem` or `moveItem`, record pairs for undo.
- `.image(data, ext)` → compute `Untitled.ext` with `appendNumber` rule, write data to disk (off main), record single path for undo.

Both branches call `onMoved()` (already exists — triggers folder reload) and register an undo.

### 3.3 Keyboard routing

`FileListNSTableView.keyDown` adds two new cases:

```swift
case 8 where event.modifierFlags.contains(.command):           // ⌘C
    copyHandler?()
case 9 where event.modifierFlags.contains(.command):           // ⌘V or ⌥⌘V
    pasteHandler?(event.modifierFlags.contains(.option) ? .move : .copy)
```

The two new closures (`copyHandler`, `pasteHandler`) are wired in `FileListView.makeNSView` the same way `deleteHandler` and `activationHandler` already are. `⌥⌘C` remains "Copy Path" (unchanged), and falls through `super.keyDown` because our ⌘C case matches `.command` exactly — we explicitly require `!event.modifierFlags.contains(.option)` to avoid stealing ⌥⌘C.

### 3.4 Menu integration

**Edit menu (`CairnApp.swift` / `EditCommands`)**: add three buttons after the existing Undo/Redo pair, using a new `@FocusedValue(\.pasteTarget)` whose type is a lightweight struct:

```swift
struct PasteTarget {
    let copy: () -> Void
    let paste: (PasteOp) -> Void
    let canCopy: () -> Bool       // any row selected
    let canPaste: () -> Bool      // pasteboard has files or image
}
```

Wired from `FileListView` via `.focusedSceneValue(\.pasteTarget, …)` the same way `tabUndoManager` is already wired.

**Context menu** (`FileListCoordinator.menu(for:)`): when the click lands in empty space (`row == -1`), show:

- "Paste" (enabled if `canPaste`)
- "Paste Item Here" (enabled if pasteboard has file URLs, not just an image)

When the click lands on a row, keep existing entries + a new "Copy" item alongside "Copy Path".

## 4. Logic Details

### 4.1 File copy (`⌘V`)

```swift
for src in urls {
    let dest = uniqueDestination(named: src.lastPathComponent, in: cwd, rule: .appendCopy)
    try FileManager.default.copyItem(at: src, to: dest)
}
```

Collision rule = `appendCopy`:

| n-th collision | Filename                |
|----------------|-------------------------|
| 0              | `foo.txt` (no suffix if name is free) |
| 1              | `foo copy.txt`          |
| 2              | `foo copy 2.txt`        |
| 3              | `foo copy 3.txt`        |

Matches Finder. Dotfiles like `.gitignore` → `.gitignore copy`. Composite extensions like `archive.tar.gz` → `archive.tar copy.gz` (Finder behavior — splits on last dot). Explicitly documented in tests.

### 4.2 File move (`⌥⌘V`)

```swift
for src in urls {
    let dest = cwd.appendingPathComponent(src.lastPathComponent)
    guard !FileManager.default.fileExists(atPath: dest.path) else {
        NSSound.beep(); continue                    // matches drag-drop policy
    }
    try FileManager.default.moveItem(at: src, to: dest)
}
```

No copy fallback on sandbox failure — silent mode-switching would surprise the user. On all-failed move, the operation is a no-op + beep; on partial success, register undo for the moves that actually landed.

### 4.3 Cairn ⌘C

Selected rows' absolute URLs are written to `NSPasteboard.general` using `NSPasteboard.writeObjects([URL])`. Finder accepts this and a subsequent Finder ⌘V yields real files. Our own ⌘V reads the same type.

`NSPasteboard.PasteboardType` emitted: `.fileURL` (via `URL` conforming to `NSPasteboardWriting`). Same type already used by drag-drop export, so drag and ⌘C stay symmetric.

### 4.4 Image paste

Trigger: pasteboard has no `.fileURL` items, but has image data.

Format priority (first match wins):

1. `NSPasteboard.PasteboardType.png` → save bytes as-is, ext = `png`.
2. `NSPasteboard.PasteboardType.tiff` → convert via `NSBitmapImageRep(data:)?.representation(using: .png, properties: [:])`, save as `png`. If conversion fails, fall through to (3).
3. `NSPasteboard.PasteboardType("public.jpeg")` → save bytes as-is, ext = `jpg`.

Filename: always `Untitled.<ext>`. Collision rule = `appendNumber` → `Untitled 2.png`, `Untitled 3.png`. Different extensions do **not** collide (`Untitled.png` and `Untitled.jpg` coexist).

Disk write happens on a background queue (`Task.detached`) to avoid blocking main when the image is large (e.g., a full-screen Retina capture is ~10 MB PNG). The main actor re-enters only to call `onMoved()` and register undo.

### 4.5 Undo / Redo

| Action                | Undo                         | Redo                    |
|-----------------------|------------------------------|-------------------------|
| Paste copy (N files)  | `removeItem` each created URL | Re-copy from source     |
| Paste move (N files)  | `moveItem` dest → src (existing `registerMoveUndo` path) | Re-move src → dest |
| Paste image           | `removeItem` created URL     | Re-write same Data      |

Copy-undo uses **hard delete** (`removeItem`), not trash. Reason: the file was created <1s ago by the user's own paste, so trashing it is friction (leaves stale Trash entry, confusing). This mirrors how most macOS apps handle paste-undo.

Undo action names for the Edit menu:

- `"Paste"` / `"Paste N Items"`
- `"Move"` / `"Move N Items"` (existing)
- `"Paste Screenshot"` for image case (distinguished so the user can tell at a glance)

### 4.6 Error handling

- Empty/irrelevant pasteboard on ⌘V → `NSSound.beep()`, no alert (matches Finder).
- Current folder not writable or no current folder → `NSAlert` "Couldn't paste: <reason>".
- Per-item failure inside a multi-file paste → beep, skip, continue. Whatever landed is undoable; what didn't is silently dropped. (Same as existing drop-move.)
- TIFF→PNG conversion failure → try JPEG branch; if all branches fail → beep.

## 5. Edge Cases

1. **Paste into the same folder the source lives in.** `cwd/foo.txt` copied → pasted → `cwd/foo copy.txt` generated. Works because `uniqueDestination` just checks filesystem presence.
2. **Paste folder into itself / descendant.** For move, `FileManager.moveItem` throws; we beep + skip. We don't pre-validate (matching the existing drag-drop code which also relies on `moveItem`'s guard).
3. **Pasteboard changes between `canPaste()` and `pasteFromClipboard()`.** `canPaste` is a best-effort enabled-state hint; the real check happens in `read()`. Stale menu state is acceptable — the user gets a beep, not a crash.
4. **Very large image paste.** Disk write is off-main. Main actor only touches `onMoved()` post-write.
5. **Dotfile name.** `.gitignore` → collision goes to `.gitignore copy` (no extension split). `uniqueDestination` detects "filename starts with `.` and has no further dot".
6. **Composite extension.** `foo.tar.gz` → `foo.tar copy.gz`. Matches Finder; split on last `.` only.
7. **Pasteboard has both `.fileURL` and image data** (rare: e.g., a screenshot taken via an app that stages both). File URL wins — this is what Finder does.
8. **Empty selection on ⌘C.** Beep.
9. **Source file deleted between Finder ⌘C and our ⌘V.** `copyItem` throws, item is skipped, whatever else landed is committed.

## 6. Testing

### 6.1 Unit tests — `apps/CairnTests/ClipboardPasteServiceTests.swift`

Pure logic, no AppKit runtime integration:

- `uniqueDestination_appendCopy_noCollision` → returns original name
- `uniqueDestination_appendCopy_firstCollision` → "foo copy.txt"
- `uniqueDestination_appendCopy_secondCollision` → "foo copy 2.txt"
- `uniqueDestination_appendCopy_dotfile` → ".gitignore copy"
- `uniqueDestination_appendCopy_compositeExtension` → "foo.tar copy.gz"
- `uniqueDestination_appendNumber_noCollision` → "Untitled.png"
- `uniqueDestination_appendNumber_firstCollision` → "Untitled 2.png"
- `uniqueDestination_appendNumber_differentExtDoesNotCollide` → Untitled.png + Untitled.jpg coexist
- `tiffToPng_smoke` → 1×1 white pixel TIFF → non-empty PNG that `NSImage(data:)` can decode
- `read_fileURLsWinOverImage` → pasteboard with both → returns `.files`
- `read_pngBeatsTiff` → pasteboard with both → returns `.image(_, "png")` from PNG branch
- `read_tiffConverted` → TIFF-only pasteboard → returns `.image(pngData, "png")`
- `read_jpegPassthrough` → JPEG-only → returns `.image(_, "jpg")`
- `read_emptyReturnsNil` → empty pasteboard → nil

Collision tests use real filesystem under `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`, cleaned up in `tearDown`.

### 6.2 Manual QA (to be documented in PR body)

- Finder ⌘C (single file) → Cairn ⌘V → file copied, row appears, ⌘Z removes it.
- Finder ⌘C (multi-select) → Cairn ⌘V → all copied, single undo removes all.
- Cairn ⌘C → Finder ⌘V → real files land in Finder.
- Cairn ⌘C → Cairn ⌘V in same folder → `foo copy.txt` created.
- Finder ⌘C → Cairn ⌥⌘V → file moved (gone from Finder source).
- ⌃⌘⇧4 screenshot → Cairn ⌘V → `Untitled.png` appears, ⌘Z removes it.
- Chrome "Copy Image" on a JPEG-backed `<img>` → Cairn ⌘V → `Untitled.png` (TIFF→PNG path) or `Untitled.jpg` (JPEG passthrough) depending on what Chrome stages.
- Empty pasteboard → Cairn ⌘V → beep.
- Context menu on empty space shows Paste items only when pasteboard has content.
- Edit menu shows "Undo Paste" after a paste.

## 7. File Inventory

**New**

- `apps/Sources/Services/ClipboardPasteService.swift` (~150 lines)
- `apps/CairnTests/ClipboardPasteServiceTests.swift` (~180 lines)

**Modified**

- `apps/Sources/Views/FileList/FileListCoordinator.swift` — `copySelectedToClipboard`, `pasteFromClipboard`, undo registrations, context-menu additions.
- `apps/Sources/Views/FileList/FileListNSTableView.swift` — keyDown cases + 2 closures.
- `apps/Sources/Views/FileList/FileListView.swift` — closure wiring + FocusedValue emission.
- `apps/Sources/CairnApp.swift` — `FocusedPasteTargetKey`, EditCommands Copy/Paste/Paste-Item-Here buttons.

## 8. Open Questions (resolved in brainstorm)

- ~~Undo-delete from Trash?~~ **Descoped.**
- ~~Paste semantics?~~ **Finder-style**: ⌘V = copy, ⌥⌘V = move.
- ~~Screenshot filename?~~ **`Untitled.<ext>`**, collision `Untitled 2.<ext>`.
- ~~TIFF policy?~~ **Convert to PNG.** Size + downstream-tool compatibility win.
- ~~Move failure fallback?~~ **None.** Beep + skip.
- ~~Cairn ⌘C included?~~ **Yes.** Required for Cairn→Finder and Cairn→Cairn symmetry.
