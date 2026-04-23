import AppKit
import SwiftUI
import QuickLookUI

/// Uniform payload for NSMenuItem.representedObject. Captures whatever the
/// target-action needs; new cases can be added by extending fields without
/// changing the handler's type checks. Covers the simple row-action menus
/// (Add-to-Pinned, Reveal, Copy Path, Move to Trash) via `entry` and the
/// Open-With submenu via the optional `appURL`.
final class MenuPayload: NSObject {
    let entry: FileEntry
    let appURL: URL?

    init(entry: FileEntry, appURL: URL? = nil) {
        self.entry = entry
        self.appURL = appURL
    }
}

/// Bridges FolderModel ↔ NSTableView.
///
/// Single class implementing both NSTableViewDataSource and NSTableViewDelegate.
/// Holds:
///   - `folder` (the @Observable model)
///   - `onActivate` (SwiftUI closure for double-click / ⏎)
///   - `lastSnapshot` (cached sorted view to avoid recomputing inside dataSource)
///   - `isApplyingModelUpdate` (re-entrancy guard during updateNSView)
final class FileListCoordinator: NSObject,
                                 NSTableViewDataSource,
                                 NSTableViewDelegate,
                                 NSTextFieldDelegate,
                                 QLPreviewPanelDataSource,
                                 QLPreviewPanelDelegate {
    private var folder: FolderModel
    private var provider: FileSystemProvider
    private var onActivate: (FileEntry) -> Void

    /// Row index currently being inline-renamed. -1 when no rename is active.
    /// Set in `renameSelected()` before `editColumn` runs and cleared in
    /// `controlTextDidEndEditing(_:)` once the commit path has finished.
    private var renamingRow: Int = -1
    /// Original basename captured at edit-start. Used to skip the FS move when
    /// the user commits an empty/whitespace-only name or presses Escape (which
    /// AppKit already reverts — we just need to avoid firing a no-op rename).
    private var renamingOriginalName: String = ""

    /// Cache of Open With app lists keyed by lowercased path extension.
    /// Invalidated on `attach(table:)` (folder switch).
    private var openWithAppsCache: [String: [URL]] = [:]
    private var openWithDefaultAppCache: [String: URL?] = [:]

    private weak var table: FileListNSTableView?
    private var lastSnapshot: [FileEntry] = []
    private var isApplyingModelUpdate = false

    private var externalEntries: [FileEntry]?
    private(set) var searchRoot: URL?
    private(set) var folderColumnVisible: Bool = false
    /// Current tab's folder root — used only by the Git column to translate
    /// each absolute entry path to a repo-relative one for set lookups.
    private var folderRoot: URL?
    /// Latest GitService snapshot for this tab's folder. Nil when the folder
    /// isn't a git repo.
    private var gitSnapshot: GitService.Snapshot?

    private let iconCache = FileListIconCache()

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private var onAddToPinned: (FileEntry) -> Void
    private var isPinnedCheck: (FileEntry) -> Bool
    private var onSelectionChanged: (FileEntry?) -> Void
    /// Called after a successful drop-move so the host can reload the folder
    /// (and trigger any side effects like search refresh). The Rust index
    /// watcher will eventually pick up the FS change too, but reloading here
    /// makes the UI feel synchronous.
    private var onMoved: () -> Void
    /// Tab-scoped undo stack. Coordinator registers inverse FS operations
    /// here after every successful move / trash so ⌘Z reverts them. Held
    /// weakly because the Tab owns the manager's lifetime; if the tab goes
    /// away mid-operation we just skip registration.
    private weak var undoManager: UndoManager?
    private var transfers: TransferController
    /// Resolves an `SshTarget` back to a provider for cross-tab drops. Needed
    /// when the destination tab is local but the source FSPath is SSH — the
    /// coordinator's own `provider` is the destination; to download we must
    /// use the source's SSH provider (shared session pool).
    private var remoteProviderResolver: (SshTarget) -> FileSystemProvider?

    init(folder: FolderModel,
         provider: FileSystemProvider,
         transfers: TransferController,
         remoteProviderResolver: @escaping (SshTarget) -> FileSystemProvider? = { _ in nil },
         onActivate: @escaping (FileEntry) -> Void,
         onAddToPinned: @escaping (FileEntry) -> Void,
         isPinnedCheck: @escaping (FileEntry) -> Bool,
         onSelectionChanged: @escaping (FileEntry?) -> Void,
         onMoved: @escaping () -> Void = {},
         undoManager: UndoManager? = nil) {
        self.folder = folder
        self.provider = provider
        self.transfers = transfers
        self.remoteProviderResolver = remoteProviderResolver
        self.onActivate = onActivate
        self.onAddToPinned = onAddToPinned
        self.isPinnedCheck = isPinnedCheck
        self.onSelectionChanged = onSelectionChanged
        self.onMoved = onMoved
        self.undoManager = undoManager
        super.init()
    }

    /// Invalidate per-folder caches without touching the NSTableView.
    /// Called from updateBindings when the FolderModel identity changes;
    /// the subsequent applyModelSnapshot in updateNSView reloads the data
    /// with the new folder's entries in a single pass.
    private func resetPerFolderCaches() {
        openWithAppsCache.removeAll()
        openWithDefaultAppCache.removeAll()
    }

    func attach(table: FileListNSTableView) {
        self.table = table
        resetPerFolderCaches()
        applyModelSnapshot(table: table)
    }

    /// Refresh captured bindings when SwiftUI re-renders FileListView with a
    /// different Tab. SwiftUI only calls `makeCoordinator()` once per view
    /// identity, so without this the coordinator keeps pointing at the very
    /// first Tab's FolderModel / navigate closure — double-clicks from a
    /// later tab then route back to the original tab. On a FolderModel
    /// identity change we additionally invalidate per-folder caches; sort
    /// indicator and selection state get re-applied by the trailing
    /// `applyModelSnapshot(table:)` call in `FileListView.updateNSView`.
    func updateBindings(folder: FolderModel,
                        provider: FileSystemProvider,
                        transfers: TransferController,
                        remoteProviderResolver: @escaping (SshTarget) -> FileSystemProvider? = { _ in nil },
                        onActivate: @escaping (FileEntry) -> Void,
                        onAddToPinned: @escaping (FileEntry) -> Void,
                        isPinnedCheck: @escaping (FileEntry) -> Bool,
                        onSelectionChanged: @escaping (FileEntry?) -> Void,
                        onMoved: @escaping () -> Void = {},
                        undoManager: UndoManager? = nil) {
        let folderChanged = self.folder !== folder
        self.folder = folder
        self.provider = provider
        self.transfers = transfers
        self.remoteProviderResolver = remoteProviderResolver
        self.onActivate = onActivate
        self.onAddToPinned = onAddToPinned
        self.isPinnedCheck = isPinnedCheck
        self.onSelectionChanged = onSelectionChanged
        self.onMoved = onMoved
        self.undoManager = undoManager
        if folderChanged {
            resetPerFolderCaches()
            // Deliberately skip applyModelSnapshot here — updateNSView will call
            // it right after setEntries() has installed the new folder's data,
            // avoiding a redundant reload with stale externalEntries.
        }
    }

#if DEBUG
    /// Test-only hook to invoke the current onActivate without routing
    /// through AppKit. Keeps unit tests decoupled from NSTableView.
    func fireActivate(entry: FileEntry) { onActivate(entry) }

    /// Test-only identity probe for asserting folder swap behaviour.
    var folderRefForTest: FolderModel { folder }
#endif

    // MARK: - Entries injection (called by FileListView.updateNSView)

    /// Replaces the default `folder.sortedEntries` with an externally-managed
    /// entries array. Pass `nil` would keep the default; to restore the default,
    /// pass `folder.sortedEntries` explicitly from the caller.
    func setEntries(_ entries: [FileEntry], searchRoot: URL?) {
        self.externalEntries = entries
        self.searchRoot = searchRoot
    }

    /// Sets the folder root used by the Git column for repo-relative path
    /// lookups. Independent of `searchRoot`.
    func setFolderRoot(_ url: URL?) {
        self.folderRoot = url
    }

    /// Sets the current Git snapshot used by the Git column. Nil when the
    /// tab's folder isn't a git repo.
    func setGitSnapshot(_ snap: GitService.Snapshot?) {
        self.gitSnapshot = snap
    }

    /// Toggles the "Folder" column used by subtree search results. Called by
    /// `FileListView.updateNSView`; idempotent on repeated calls.
    func setFolderColumnVisible(_ visible: Bool) {
        guard let table = self.table else {
            folderColumnVisible = visible
            return
        }
        let existing = table.tableColumns.first(where: { $0.identifier == .folder })
        if visible, existing == nil {
            let col = NSTableColumn(identifier: .folder)
            col.title = "Folder"
            col.minWidth = 80
            col.width = 180
            // Insert immediately after the Name column so the user sees the
            // relative-path context next to the file name.
            table.addTableColumn(col)
            if let nameIdx = table.tableColumns.firstIndex(where: { $0.identifier == .name }) {
                let lastIdx = table.tableColumns.count - 1
                if lastIdx != nameIdx + 1 {
                    table.moveColumn(lastIdx, toColumn: nameIdx + 1)
                }
            }
        } else if !visible, let col = existing {
            table.removeTableColumn(col)
        }
        folderColumnVisible = visible
    }

    // MARK: - Snapshot application (called from updateNSView)

    /// Pulls the latest sortedEntries into NSTableView and re-applies the
    /// selection set, suppressing the delegate's selection-change callback.
    func applyModelSnapshot(table: NSTableView) {
        isApplyingModelUpdate = true
        defer { isApplyingModelUpdate = false }

        lastSnapshot = externalEntries ?? folder.sortedEntries
        table.reloadData()

        // Restore selection (path-based).
        let indexes = NSMutableIndexSet()
        for (i, entry) in lastSnapshot.enumerated() {
            if folder.selection.contains(entry.path.toString()) {
                indexes.add(i)
            }
        }
        table.selectRowIndexes(indexes as IndexSet, byExtendingSelection: false)

        // Reflect sortDescriptor in column headers (visual indicator).
        let nsDesc = NSSortDescriptor(
            key: keyString(for: folder.sortDescriptor.field),
            ascending: folder.sortDescriptor.order == .ascending
        )
        if table.sortDescriptors != [nsDesc] {
            table.sortDescriptors = [nsDesc]
        }
    }

    // MARK: - DataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        lastSnapshot.count
    }

    // MARK: - Delegate (view-based cells)

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = FileListRowView()
        if row < lastSnapshot.count {
            // Dim hidden entries so the user can tell them apart at a glance
            // when ⌘⇧. is toggled on. Alpha propagates to subviews, so both
            // the icon and text field dim together.
            rowView.alphaValue = lastSnapshot[row].is_hidden ? 0.55 : 1.0
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let column, row < lastSnapshot.count else { return nil }
        let entry = lastSnapshot[row]
        let identifier = column.identifier
        let cellId = NSUserInterfaceItemIdentifier("cell.\(identifier.rawValue)")

        let cell = (tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView)
            ?? makeCell(identifier: cellId, kind: identifier)

        switch identifier {
        case .name:
            cell.imageView?.image = systemImage(for: entry)
            cell.textField?.stringValue = entry.name.toString()
            cell.textField?.alignment = .left
            // Name fields are editable-capable (see makeCell) but must look like
            // labels until the user explicitly starts a rename. Cells are
            // recycled across rows, so reset the edit-mode chrome on every
            // bind — otherwise a previously-renamed row could leak its bezel
            // to whatever row reuses its view after scrolling.
            if row != renamingRow {
                if let tf = cell.textField {
                    tf.isEditable = false
                    tf.isSelectable = false
                    tf.isBordered = false
                    tf.drawsBackground = false
                }
            }
        case .size:
            cell.textField?.stringValue = entry.kind == .Directory
                ? "—"
                : byteFormatter.string(fromByteCount: Int64(entry.size))
            cell.textField?.alignment = .right
        case .modified:
            // Rust walker yields modified_unix == 0 when the filesystem returns
            // no mtime (broken symlink, permission-gated metadata). Surface as
            // "—" instead of showing 1970-01-01.
            let date = Date(timeIntervalSince1970: TimeInterval(entry.modified_unix))
            cell.textField?.stringValue = entry.modified_unix == 0 ? "—" : dateFormatter.string(from: date)
            cell.textField?.alignment = .right
        case .folder:
            cell.imageView?.image = nil
            let full = entry.path.toString()
            let rel: String
            if let rootPath = searchRoot?.standardizedFileURL.path, full.hasPrefix(rootPath) {
                var r = String(full.dropFirst(rootPath.count))
                if r.hasPrefix("/") { r.removeFirst() }
                // Strip filename — only show the parent folder relative to search root.
                rel = (r as NSString).deletingLastPathComponent
            } else {
                // Fallback for entries outside searchRoot (shouldn't happen in practice).
                rel = (full as NSString).deletingLastPathComponent
            }
            cell.textField?.stringValue = rel.isEmpty ? "—" : rel
            cell.textField?.alignment = .left
        case .git:
            cell.imageView?.image = nil
            let full = entry.path.toString()
            let rootPath = folderRoot?.standardizedFileURL.path ?? ""
            let rel: String
            if !rootPath.isEmpty, full.hasPrefix(rootPath) {
                var r = String(full.dropFirst(rootPath.count))
                if r.hasPrefix("/") { r.removeFirst() }
                rel = r
            } else {
                rel = full
            }
            let symbol: String
            let color: NSColor
            // Single dict lookup (was 4 sequential set probes per row → 40K
            // hashes per render on a 10K-row folder; now 10K).
            let status: GitService.GitStatus? = gitSnapshot?.statusByPath[rel] ?? nil
            switch status {
            case .modified:  symbol = "M";  color = .systemYellow
            case .added:     symbol = "A";  color = .systemGreen
            case .deleted:   symbol = "D";  color = .systemRed
            case .untracked: symbol = "??"; color = .secondaryLabelColor
            case nil:        symbol = "—";  color = .tertiaryLabelColor
            }
            cell.textField?.stringValue = symbol
            cell.textField?.textColor = color
            cell.textField?.alignment = .center
        default:
            cell.textField?.stringValue = ""
        }
        return cell
    }

    // MARK: - Sort

    /// AppKit fires this both from user clicks on column headers AND as a
    /// side effect of `table.sortDescriptors = [...]` inside `applyModelSnapshot`.
    /// The `isApplyingModelUpdate` guard prevents the second path from
    /// re-entering and triggering a redundant model update.
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if isApplyingModelUpdate { return }
        guard let new = tableView.sortDescriptors.first,
              let key = new.key,
              let field = sortField(for: key) else { return }

        let order: FolderModel.SortOrder = new.ascending ? .ascending : .descending
        folder.setSortDescriptor(.init(field: field, order: order))
        // Reapply snapshot to re-sort + restore selection.
        applyModelSnapshot(table: tableView)
    }

    // MARK: - Selection

    func tableViewSelectionDidChange(_ notification: Notification) {
        if isApplyingModelUpdate { return }
        guard let table = notification.object as? NSTableView else { return }
        let rows = table.selectedRowIndexes
        let paths = rows.compactMap { row -> String? in
            guard row < lastSnapshot.count else { return nil }
            return lastSnapshot[row].path.toString()
        }
        folder.setSelection(Set(paths))

        // Preview focus: first-selected row's entry (row-order, not Set-order).
        let firstRow = rows.min()
        let firstEntry: FileEntry? = firstRow.flatMap { row in
            row < lastSnapshot.count ? lastSnapshot[row] : nil
        }
        onSelectionChanged(firstEntry)
    }

    // MARK: - Activation (double-click + ⏎)

    @objc func handleDoubleClick(_ sender: Any?) {
        guard let table = sender as? NSTableView else { return }
        let row = table.clickedRow
        guard row >= 0, row < lastSnapshot.count else { return }
        onActivate(lastSnapshot[row])
    }

    // MARK: - Inline rename (⏎)

    /// Kicks off Finder-style inline rename on the focused row. Bound to
    /// ⏎/numpad-Enter via `FileListNSTableView.renameHandler`. Opening a file
    /// is intentionally NOT bound here — that path lives on double-click and
    /// ⌘↓ so Enter is free for the (far more frequent) rename gesture.
    ///
    /// Multi-selection: beeps. Batch rename would need a dedicated sheet and
    /// isn't worth the complexity at this stage.
    func renameSelected() {
        guard let table = self.table else { return }
        let rows = table.selectedRowIndexes
        guard rows.count == 1, let row = rows.first, row < lastSnapshot.count else {
            NSSound.beep(); return
        }
        guard let nameColIdx = table.tableColumns.firstIndex(where: { $0.identifier == .name }) else { return }
        guard let cell = table.view(atColumn: nameColIdx, row: row, makeIfNecessary: true) as? NSTableCellView,
              let tf = cell.textField else { return }

        renamingRow = row
        renamingOriginalName = lastSnapshot[row].name.toString()

        tf.isEditable = true
        tf.isSelectable = true
        tf.isBordered = true
        tf.drawsBackground = true
        tf.backgroundColor = .textBackgroundColor

        table.editColumn(nameColIdx, row: row, with: nil, select: false)

        // Finder selects just the basename (without extension). If the entry
        // is a directory or has no extension, everything is selected.
        if let editor = tf.currentEditor() as? NSTextView {
            let full = tf.stringValue as NSString
            let ext = full.pathExtension
            // NSRange is UTF-16-based to match NSString/NSTextView; using
            // `count` on a Swift String would drift on extended grapheme
            // clusters (emoji filenames etc.).
            let length = (ext.isEmpty || lastSnapshot[row].kind == .Directory)
                ? full.length
                : (full.deletingPathExtension as NSString).length
            editor.setSelectedRange(NSRange(location: 0, length: length))
        }
    }

    /// NSTextFieldDelegate — Return, Tab, click-out, Escape all land here.
    /// Escape is pre-handled by AppKit (it reverts `stringValue` before the
    /// notification fires), so the unchanged-value branch covers it.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let tf = notification.object as? NSTextField else { return }

        let row = renamingRow
        renamingRow = -1

        // Restore label chrome so the row looks identical to its neighbours.
        tf.isEditable = false
        tf.isSelectable = false
        tf.isBordered = false
        tf.drawsBackground = false

        guard row >= 0, row < lastSnapshot.count else { return }
        let newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldName = renamingOriginalName

        if newName.isEmpty || newName == oldName {
            tf.stringValue = oldName
            return
        }
        // Path separators would create a move, not a rename. Reject like Finder.
        if newName.contains("/") || newName.contains(":") {
            tf.stringValue = oldName
            NSSound.beep(); return
        }

        let entry = lastSnapshot[row]
        let oldPath = FSPath(provider: provider.identifier, path: entry.path.toString())
        guard let parent = oldPath.parent() else { return }
        let newPath = parent.appending(newName)

        if case .ssh = provider.identifier {
            // Remote rename — no undo in v1
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.provider.rename(from: oldPath, to: newPath)
                    await MainActor.run { self.onMoved() }
                } catch {
                    await MainActor.run {
                        tf.stringValue = oldName
                        NSSound.beep()
                    }
                }
            }
        } else {
            // Local rename — existing FileManager path with undo
            let oldURL = URL(fileURLWithPath: entry.path.toString())
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)

            if FileManager.default.fileExists(atPath: newURL.path) {
                tf.stringValue = oldName
                NSSound.beep(); return
            }

            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                registerRenameUndo(from: oldURL, to: newURL)
                onMoved()
            } catch {
                tf.stringValue = oldName
                NSSound.beep()
            }
        }
    }

    private func registerRenameUndo(from oldURL: URL, to newURL: URL) {
        guard let undoManager else { return }
        let onMoved = self.onMoved
        let target = self
        undoManager.registerUndo(withTarget: target) { _ in
            try? FileManager.default.moveItem(at: newURL, to: oldURL)
            onMoved()
            undoManager.registerUndo(withTarget: target) { coord in
                coord.replayRename(from: oldURL, to: newURL)
            }
        }
        undoManager.setActionName("Rename")
    }

    private func replayRename(from oldURL: URL, to newURL: URL) {
        if (try? FileManager.default.moveItem(at: oldURL, to: newURL)) != nil {
            registerRenameUndo(from: oldURL, to: newURL)
            onMoved()
        }
    }

    // MARK: - Activation (⌘↓ + double-click)

    /// Invoked by ⌘↓ (toolbar button). Enters a single-selected folder; beeps
    /// on multi-selection or a non-folder selection. Files are intentionally
    /// not opened here — Cairn routes that through double-click / NSWorkspace.
    func descendIntoSelected() {
        guard let table = self.table else { return }
        let rows = table.selectedRowIndexes
        guard rows.count == 1, let row = rows.first, row < lastSnapshot.count else {
            NSSound.beep(); return
        }
        let entry = lastSnapshot[row]
        guard entry.kind == .Directory else { NSSound.beep(); return }
        onActivate(entry)
    }

    // MARK: - Right-click menu

    /// Builds a menu for the row located at the given event's window point.
    /// Returns nil when the click misses all rows (empty area).
    /// Called by FileListNSTableView.menu(for:) via menuHandler closure.
    func menu(for event: NSEvent) -> NSMenu? {
        guard let table = self.table else { return nil }
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        if row < 0 || row >= lastSnapshot.count {
            return emptySpaceMenu()
        }
        let entry = lastSnapshot[row]

        let menu = NSMenu()

        if entry.kind == .Directory {
            let item = NSMenuItem(
                title: isPinnedCheck(entry) ? "Unpin" : "Add to Pinned",
                action: #selector(menuAddToPinned(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = MenuPayload(entry: entry)
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let reveal = NSMenuItem(title: "Reveal in Finder",
                                action: #selector(menuRevealInFinder(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = MenuPayload(entry: entry)
        menu.addItem(reveal)

        // Copy (⌘C) — writes the entry's URL to the pasteboard so Finder or
        // another Cairn tab can ⌘V the real file. Distinct from Copy Path (⌥⌘C).
        let copyItem = NSMenuItem(title: "Copy",
                                  action: #selector(menuCopyEntry(_:)),
                                  keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.target = self
        copyItem.representedObject = MenuPayload(entry: entry)
        menu.addItem(copyItem)

        // Copy Path (⌥⌘C) — stays just below Reveal so the two OS-level ops sit together.
        let copyPath = NSMenuItem(title: "Copy Path",
                                  action: #selector(menuCopyPath(_:)),
                                  keyEquivalent: "c")
        copyPath.keyEquivalentModifierMask = [.command, .option]
        copyPath.target = self
        copyPath.representedObject = MenuPayload(entry: entry)
        menu.addItem(copyPath)

        // Open With submenu — non-directories only. Directories go straight to Finder.
        if entry.kind != .Directory {
            if let openWith = buildOpenWithSubmenu(for: entry) {
                let openItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                openItem.submenu = openWith
                menu.addItem(openItem)
            }
        }

        menu.addItem(.separator())

        // Move to Trash (⌘⌫) — destructive, separated by divider.
        let trash = NSMenuItem(title: "Move to Trash",
                               action: #selector(menuMoveToTrash(_:)),
                               keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!))
        trash.keyEquivalentModifierMask = .command
        trash.target = self
        trash.representedObject = MenuPayload(entry: entry)
        menu.addItem(trash)

        return menu
    }

    /// Right-click on empty space: New Folder (always) + Paste / Paste Item
    /// Here when the pasteboard has content.
    private func emptySpaceMenu() -> NSMenu? {
        let menu = NSMenu()

        // New Folder — available for all providers
        let newFolderItem = NSMenuItem(title: "New Folder",
                                       action: #selector(menuNewFolder(_:)),
                                       keyEquivalent: "")
        newFolderItem.target = self
        menu.addItem(newFolderItem)

        let pasted = ClipboardPasteService.read(from: .general)
        if let pasted {
            menu.addItem(.separator())
            let pasteItem = NSMenuItem(title: "Paste",
                                       action: #selector(NSText.paste(_:)),
                                       keyEquivalent: "v")
            pasteItem.keyEquivalentModifierMask = [.command]
            menu.addItem(pasteItem)
            // "Paste Item Here" only makes sense for real files — an image on the
            // clipboard has no source to move away from.
            if case .files = pasted {
                let moveItem = NSMenuItem(title: "Paste Item Here",
                                          action: #selector(CairnResponder.pasteItemHere(_:)),
                                          keyEquivalent: "v")
                moveItem.keyEquivalentModifierMask = [.command, .option]
                menu.addItem(moveItem)
            }
        }

        return menu
    }

    @objc private func menuNewFolder(_ sender: Any?) {
        guard let parent = folder.currentPath else { return }
        let target = parent.appending("untitled folder")
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.provider.mkdir(target)
                await MainActor.run { self.onMoved() }
            } catch {
                await MainActor.run { NSSound.beep() }
            }
        }
    }

    /// Returns the cached (apps, defaultApp) for the given file URL's extension.
    /// Populates the cache on first miss. The default-app slot is nullable —
    /// some file types have no registered default; we still want to cache the
    /// "none" answer to avoid repeated `urlForApplication` probes.
    private func appsForOpening(_ fileURL: URL) -> (apps: [URL], defaultApp: URL?) {
        let key = fileURL.pathExtension.lowercased()
        let apps: [URL]
        if let cached = openWithAppsCache[key] {
            apps = cached
        } else {
            apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            openWithAppsCache[key] = apps
        }
        let def: URL?
        if let cachedDef = openWithDefaultAppCache[key] {
            def = cachedDef
        } else {
            def = NSWorkspace.shared.urlForApplication(toOpen: fileURL)
            openWithDefaultAppCache[key] = def
        }
        return (apps, def)
    }

    private func buildOpenWithSubmenu(for entry: FileEntry) -> NSMenu? {
        let fileURL = URL(fileURLWithPath: entry.path.toString())
        let (appURLs, defaultApp) = appsForOpening(fileURL)
        guard !appURLs.isEmpty else { return nil }

        let submenu = NSMenu()
        let defaultCanon = defaultApp?.standardizedFileURL

        // Default app goes first; remaining apps are deduped against it using
        // the standardized form so symlink / alias variants don't double-up.
        var ordered: [URL] = []
        if let def = defaultApp {
            ordered.append(def)
            ordered.append(contentsOf: appURLs.filter { $0.standardizedFileURL != defaultCanon })
        } else {
            ordered = appURLs
        }

        for appURL in ordered {
            // `displayName(atPath:)` already strips the `.app` bundle suffix
            // and returns the localized display name; no further massage needed.
            let name = FileManager.default.displayName(atPath: appURL.path)
            let title = (appURL.standardizedFileURL == defaultCanon) ? "\(name) (default)" : name
            let item = NSMenuItem(title: title,
                                  action: #selector(menuOpenWith(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = MenuPayload(entry: entry, appURL: appURL)
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func menuAddToPinned(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload else { return }
        onAddToPinned(payload.entry)
    }

    @objc private func menuRevealInFinder(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload else { return }
        NSWorkspace.shared.selectFile(payload.entry.path.toString(),
                                      inFileViewerRootedAtPath: "")
    }

    @objc private func menuCopyPath(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload else { return }
        let path = payload.entry.path.toString()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
    }

    @objc private func menuCopyEntry(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload else { return }
        let url = URL(fileURLWithPath: payload.entry.path.toString())
        ClipboardPasteService.writeFileURLs([url], to: .general)
    }

    @objc private func menuMoveToTrash(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload else { return }
        let url = URL(fileURLWithPath: payload.entry.path.toString())
        var trashedURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
            registerTrashUndo(originalURL: url, trashedURL: trashedURL as URL?)
            onMoved()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't move to Trash"
            alert.informativeText = "\(url.lastPathComponent): \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Called by FileListNSTableView on ⌘⌫. Trashes every currently-selected
    /// row (local) or permanently deletes with a confirmation sheet (remote).
    func deleteSelected() {
        guard let table = self.table else { return }
        let indexes = table.selectedRowIndexes
        guard !indexes.isEmpty else { return }

        if case .ssh = provider.identifier {
            let victims = indexes.compactMap { idx -> FileEntry? in
                idx < lastSnapshot.count ? lastSnapshot[idx] : nil
            }
            let paths = victims.map { FSPath(provider: provider.identifier, path: $0.path.toString()) }
            confirmRemoteDelete(items: victims) { [weak self] confirmed in
                guard let self, confirmed else { return }
                Task {
                    do {
                        try await self.provider.delete(paths)
                        await MainActor.run { self.onMoved() }
                    } catch {
                        await MainActor.run { NSSound.beep() }
                    }
                }
            }
        } else {
            // Collect (orig, trashed-location) pairs so a single ⌘Z restores
            // every file from one ⌘⌫. Without grouping the user would have to
            // hit ⌘Z N times to undo a multi-select trash.
            var pairs: [(URL, URL)] = []
            for idx in indexes where idx >= 0 && idx < lastSnapshot.count {
                let url = URL(fileURLWithPath: lastSnapshot[idx].path.toString())
                var trashed: NSURL?
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                    if let t = trashed as URL? { pairs.append((url, t)) }
                } catch {
                    NSSound.beep()
                }
            }
            if !pairs.isEmpty {
                registerBatchTrashUndo(pairs)
                onMoved()
            }
        }
    }

    private func confirmRemoteDelete(items: [FileEntry], completion: @escaping (Bool) -> Void) {
        let hostSummary: String = {
            if case .ssh(let t) = provider.identifier { return "\(t.user)@\(t.hostname)" }
            return ""
        }()
        let parent = folder.currentPath?.path ?? "/"
        RemoteDeleteConfirm.present(
            hostSummary: hostSummary,
            parent: parent,
            names: items.map { $0.name.toString() },
            completion: completion
        )
    }

    /// Pushes "move trashed file back to original location" onto the undo
    /// stack. The redo handler re-trashes — symmetric so ⌘⇧Z works.
    private func registerTrashUndo(originalURL: URL, trashedURL: URL?) {
        guard let undoManager, let trashedURL else { return }
        let onMoved = self.onMoved
        let target = self
        undoManager.registerUndo(withTarget: target) { _ in
            do {
                try FileManager.default.moveItem(at: trashedURL, to: originalURL)
                onMoved()
                undoManager.registerUndo(withTarget: target) { coord in
                    coord.menuMoveToTrashURL(originalURL)
                }
            } catch {
                NSSound.beep()
            }
        }
        undoManager.setActionName("Move to Trash")
    }

    private func registerBatchTrashUndo(_ pairs: [(URL, URL)]) {
        guard let undoManager else { return }
        let onMoved = self.onMoved
        let target = self
        undoManager.registerUndo(withTarget: target) { _ in
            for (orig, trashed) in pairs {
                try? FileManager.default.moveItem(at: trashed, to: orig)
            }
            onMoved()
            undoManager.registerUndo(withTarget: target) { coord in
                coord.batchTrash(originalURLs: pairs.map { $0.0 })
            }
        }
        undoManager.setActionName(pairs.count == 1 ? "Move to Trash" : "Move \(pairs.count) Items to Trash")
    }

    /// Plumbing for redo paths — same as menuMoveToTrash but takes the URL
    /// directly instead of a menu payload.
    private func menuMoveToTrashURL(_ url: URL) {
        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            registerTrashUndo(originalURL: url, trashedURL: trashed as URL?)
            onMoved()
        } catch {
            NSSound.beep()
        }
    }

    private func batchTrash(originalURLs urls: [URL]) {
        var pairs: [(URL, URL)] = []
        for url in urls {
            var trashed: NSURL?
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: &trashed)) != nil,
               let t = trashed as URL? {
                pairs.append((url, t))
            }
        }
        if !pairs.isEmpty {
            registerBatchTrashUndo(pairs)
            onMoved()
        }
    }

    @objc private func menuOpenWith(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload, let appURL = payload.appURL else { return }
        let p = FSPath(provider: provider.identifier, path: payload.entry.path.toString())
        Task { [weak self] in
            guard let self else { return }
            let fileURL: URL
            if case .ssh = p.provider {
                guard let cached = try? await self.provider.downloadToCache(p) else {
                    await MainActor.run { NSSound.beep() }
                    return
                }
                fileURL = cached
            } else {
                fileURL = URL(fileURLWithPath: payload.entry.path.toString())
            }
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL,
                                    configuration: .init()) { _, error in
                if let error { NSLog("cairn: Open With failed — \(error.localizedDescription)") }
            }
        }
    }

    // MARK: - Quick Look

    /// URLs QL should preview. Captured once in `snapshotQuickLookURLs` when
    /// the panel takes control, then read unchanged by AppKit's data-source
    /// queries. Previously computed every call, which raced with live
    /// selection changes while the panel was up.
    private var quickLookSnapshot: [URL] = []

    /// Called by `FileListNSTableView.beginPreviewPanelControl`. Freezes the
    /// current selection (or the first row as fallback) so navigation inside
    /// the panel stays stable.
    func snapshotQuickLookURLs() {
        let selectedRows = table?.selectedRowIndexes ?? IndexSet()
        var localPaths: [URL] = []
        var remotePaths: [FSPath] = []

        let rows = selectedRows.isEmpty ? (lastSnapshot.isEmpty ? [] : [0]) : Array(selectedRows)
        for row in rows {
            guard row < lastSnapshot.count else { continue }
            let entry = lastSnapshot[row]
            let p = FSPath(provider: provider.identifier, path: entry.path.toString())
            if case .local = p.provider {
                localPaths.append(URL(fileURLWithPath: entry.path.toString()))
            } else {
                remotePaths.append(p)
            }
        }

        if remotePaths.isEmpty {
            quickLookSnapshot = localPaths.isEmpty && !lastSnapshot.isEmpty
                ? [URL(fileURLWithPath: lastSnapshot[0].path.toString())]
                : localPaths
            return
        }

        // Remote: start with empty snapshot (QL shows loading), download async, then reload
        quickLookSnapshot = localPaths
        Task { [weak self] in
            guard let self else { return }
            var downloaded: [URL] = []
            for path in remotePaths {
                if let url = try? await self.provider.downloadToCache(path) {
                    downloaded.append(url)
                }
            }
            await MainActor.run {
                self.quickLookSnapshot = localPaths + downloaded
                if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                    QLPreviewPanel.shared().reloadData()
                }
            }
        }
    }

    /// Called by `FileListNSTableView.endPreviewPanelControl`.
    func clearQuickLookSnapshot() {
        quickLookSnapshot = []
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookSnapshot.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < quickLookSnapshot.count else { return nil }
        return quickLookSnapshot[index] as NSURL
    }

    // MARK: - Private helpers

    private func makeCell(identifier: NSUserInterfaceItemIdentifier, kind: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField: NSTextField
        if kind == .name {
            // Name cells must be able to flip into an editable field when the
            // user presses ⏎ (see renameSelected). `labelWithString(_:)` hard-
            // wires isEditable/isSelectable=false and can't be reverted
            // reliably, so we build a plain NSTextField configured to *look*
            // like a label.
            textField = NSTextField()
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = false
            textField.isSelectable = false
            textField.textColor = .labelColor
            textField.delegate = self
        } else {
            textField = NSTextField(labelWithString: "")
        }
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.font = .systemFont(ofSize: 12)
        textField.cell?.usesSingleLineMode = true
        cell.addSubview(textField)
        cell.textField = textField

        if kind == .name {
            // Name column gets an icon + label.
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    private func systemImage(for entry: FileEntry) -> NSImage? {
        iconCache.icon(forPath: entry.path.toString(),
                       isDirectory: entry.kind == .Directory)
    }

    private func keyString(for field: FolderModel.SortField) -> String {
        switch field {
        case .name: return "name"
        case .size: return "size"
        case .modified: return "modified"
        }
    }

    private func sortField(for key: String) -> FolderModel.SortField? {
        switch key {
        case "name": return .name
        case "size": return .size
        case "modified": return .modified
        default: return nil
        }
    }

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
        let paths = indexes.compactMap { idx -> FSPath? in
            guard idx >= 0, idx < lastSnapshot.count else { return nil }
            return FSPath(provider: provider.identifier,
                          path: lastSnapshot[idx].path.toString())
        }
        guard !paths.isEmpty else { return }
        ClipboardPasteService.writeFSPaths(paths, to: .general)
    }

    /// Entry point for ⌘V and ⌥⌘V. Reads the general pasteboard, dispatches
    /// on content + operation, and registers undo for anything that lands.
    ///
    /// Currently handles `.files` + `.copy`. `.files` + `.move` and `.image`
    /// branches are added in later tasks.
    func pasteFromClipboard(operation: PasteOp) {
        guard let currentPath = folder.currentPath else { NSSound.beep(); return }
        guard let content = ClipboardPasteService.read(from: .general) else {
            NSSound.beep(); return
        }

        // Remote-source paste: route by (source, target) like drag-drop.
        if case .remoteFiles(let sources) = content {
            pasteRemote(sources: sources, into: currentPath)
            return
        }

        // Local-source paste targeting an SSH tab: upload.
        if case .files(let urls) = content, case .ssh = provider.identifier {
            pasteLocalToSSH(urls: urls, into: currentPath)
            return
        }

        // Clipboard image (screenshot etc.) targeting an SSH tab: materialise
        // the bytes to a temp file and upload. Without this branch the paste
        // silently fell through to the local-only `pasteImage` path, which
        // demands `folder.currentFolder` (nil for remote tabs).
        if case .image(let data, let ext) = content, case .ssh = provider.identifier {
            pasteImageToSSH(data: data, ext: ext, into: currentPath)
            return
        }

        // Local-source, local-target: existing FileManager paths.
        guard let dir = folder.currentFolder else { NSSound.beep(); return }
        guard FileManager.default.isWritableFile(atPath: dir.path) else {
            showPasteAlert("The current folder isn't writable.")
            return
        }
        switch (content, operation) {
        case (.files(let urls), .copy):
            pasteCopy(urls: urls, into: dir)
        case (.files(let urls), .move):
            pasteMove(urls: urls, into: dir)
        case (.image(let data, let ext), _):
            pasteImage(data: data, ext: ext, into: dir)
        case (.remoteFiles, _):
            break  // handled above
        }
    }

    private func pasteRemote(sources: [FSPath], into target: FSPath) {
        for src in sources {
            let dst = target.appending(src.lastComponent)
            switch (src.provider, target.provider) {
            case (.ssh(let sT), .ssh(let dT)) where sT == dT:
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.provider.copyInPlace(from: src, to: dst)
                        await MainActor.run { self.onMoved() }
                    } catch {
                        await MainActor.run { NSSound.beep() }
                    }
                }
            case (.ssh(let sT), .local):
                guard let srcProvider = remoteProviderResolver(sT) else {
                    NSSound.beep(); continue
                }
                let localDst = URL(fileURLWithPath: target.path)
                    .appendingPathComponent(src.lastComponent)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.transfers.enqueue(source: src, destination: dst, sizeHint: nil) { job, progress in
                        try await srcProvider.downloadToLocal(src, toLocalURL: localDst, progress: progress, cancel: job.cancel)
                    }
                }
            case (.local, .ssh):
                let localSrc = URL(fileURLWithPath: src.path)
                let size = (try? FileManager.default.attributesOfItem(atPath: localSrc.path))?[.size] as? Int64
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.transfers.enqueue(source: src, destination: dst, sizeHint: size) { [weak self] job, progress in
                        guard let self else { return }
                        try await self.provider.uploadFromLocal(localSrc, to: dst, progress: progress, cancel: job.cancel)
                    }
                }
            case (.local, .local):
                if let dir = folder.currentFolder {
                    pasteCopy(urls: [URL(fileURLWithPath: src.path)], into: dir)
                }
            default:
                NSSound.beep()  // unsupported (e.g. ssh→ssh cross-host)
            }
        }
    }

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
                    tmpURL,
                    to: dstPath,
                    progress: progress,
                    cancel: job.cancel
                )
            }
        }
    }

    private func pasteLocalToSSH(urls: [URL], into target: FSPath) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for src in urls {
                let dst = target.appending(src.lastPathComponent)
                let size = (try? FileManager.default.attributesOfItem(atPath: src.path))?[.size] as? Int64
                self.transfers.enqueue(source: FSPath(provider: .local, path: src.path),
                                       destination: dst, sizeHint: size) { [weak self] job, progress in
                    guard let self else { return }
                    try await self.provider.uploadFromLocal(src, to: dst, progress: progress, cancel: job.cancel)
                }
            }
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
}

// MARK: - Drag & drop (file move)
//
// Drag source: local rows export the absolute file URL via the standard
// `.fileURL` pasteboard type (Finder-compatible). Remote (SSH) rows export a
// JSON-encoded FSPath via the custom `.cairnFSPath` type so cross-provider
// drops can route to the correct transfer path.
//
// Drop target: when the proposed drop is .on a folder row, accept the drop
// and route by (source provider, destination provider):
//   local→local:         FileManager.moveItem + undo (existing)
//   local→ssh:           upload via TransferController
//   ssh(same)→ssh(same): server-side copyInPlace
//   ssh→local:           download via TransferController
extension NSPasteboard.PasteboardType {
    static let cairnFSPath = NSPasteboard.PasteboardType("com.cairn.fspath")
}

extension FileListCoordinator {
    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < lastSnapshot.count else { return nil }
        let entry = lastSnapshot[row]
        switch provider.identifier {
        case .local:
            return URL(fileURLWithPath: entry.path.toString()) as NSURL
        case .ssh:
            let item = NSPasteboardItem()
            let path = FSPath(provider: provider.identifier, path: entry.path.toString())
            guard let data = try? JSONEncoder().encode(path) else { return nil }
            item.setData(data, forType: .cairnFSPath)
            return item
        }
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        let pb = info.draggingPasteboard
        let hasFileURL = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasCairnPath = pb.data(forType: .cairnFSPath) != nil
        guard hasFileURL || hasCairnPath else { return [] }

        // Reject cross-host ssh→ssh: can't server-side copy across hosts.
        if hasCairnPath,
           let data = pb.data(forType: .cairnFSPath),
           let srcPath = try? JSONDecoder().decode(FSPath.self, from: data),
           case .ssh(let srcTarget) = srcPath.provider,
           case .ssh(let dstTarget) = provider.identifier,
           srcTarget != dstTarget {
            return []
        }

        // Pick the drag operation that matches what we'll actually do:
        //   local → ssh / ssh → local / ssh(same) → ssh(same): .copy
        //     (uploads / downloads / server-side copies don't delete the source)
        //   local → local: .move (existing FileManager.moveItem flow)
        // Returning `.move` to a Finder drag whose source is read-only makes
        // AppKit reject the drop on some macOS versions; `.copy` is always
        // honoured for external drags onto Cairn's SSH pane.
        let preferredOp: NSDragOperation = {
            switch provider.identifier {
            case .local:
                if hasCairnPath, let data = pb.data(forType: .cairnFSPath),
                   let srcPath = try? JSONDecoder().decode(FSPath.self, from: data),
                   case .ssh = srcPath.provider {
                    return .copy  // ssh → local download
                }
                return .move
            case .ssh:
                return .copy
            }
        }()

        // Drop modes:
        //   .on + directory row  → drop into that folder (existing)
        //   empty-space / below-all-rows → drop into currently-displayed folder
        // We retarget empty-space drops by rewriting proposedRow / op.
        let droppingOnRow = op == .on && row >= 0 && row < lastSnapshot.count
            && lastSnapshot[row].kind == .Directory

        if droppingOnRow {
            let targetURL = URL(fileURLWithPath: lastSnapshot[row].path.toString())
            if hasFileURL, let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                for src in urls {
                    if src.standardizedFileURL.path == targetURL.standardizedFileURL.path { return [] }
                    if targetURL.standardizedFileURL.path.hasPrefix(src.standardizedFileURL.path + "/") { return [] }
                }
            }
            return preferredOp
        }

        // Empty-space drop: retarget to the current folder (row = count, op = .above).
        // Highlights the whole table as the drop zone instead of a stray last row.
        if folder.currentPath != nil {
            tableView.setDropRow(lastSnapshot.count, dropOperation: .above)
            return preferredOp
        }
        return []
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation op: NSTableView.DropOperation) -> Bool {
        // Determine the target directory:
        //   .on a directory row      → that row
        //   .above / past-end / etc. → currently-displayed folder
        let targetPath: FSPath
        if op == .on, row >= 0, row < lastSnapshot.count,
           lastSnapshot[row].kind == .Directory {
            targetPath = FSPath(provider: provider.identifier,
                                path: lastSnapshot[row].path.toString())
        } else if let current = folder.currentPath {
            targetPath = current
        } else {
            return false
        }
        let pb = info.draggingPasteboard

        // --- Remote source: .cairnFSPath ---
        if let data = pb.data(forType: .cairnFSPath),
           let sourcePath = try? JSONDecoder().decode(FSPath.self, from: data) {
            switch (sourcePath.provider, provider.identifier) {
            case (.ssh(let srcTarget), .ssh(let dstTarget)) where srcTarget == dstTarget:
                // Same-host copy: server-side
                let dstPath = targetPath.appending(sourcePath.lastComponent)
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await provider.copyInPlace(from: sourcePath, to: dstPath)
                        await MainActor.run { self.onMoved() }
                    } catch {
                        await MainActor.run { NSSound.beep() }
                    }
                }
                return true
            case (.ssh(let srcTarget), .local):
                // Remote→local: download through the SOURCE ssh provider.
                // `self.provider` here is LocalFileSystemProvider (destination)
                // which can't fetch over sftp; resolve the source's ssh
                // provider via the shared pool.
                guard let srcProvider = remoteProviderResolver(srcTarget) else {
                    NSSound.beep()
                    return false
                }
                let localDst = URL(fileURLWithPath: targetPath.path)
                    .appendingPathComponent(sourcePath.lastComponent)
                let dstPath = FSPath(provider: .local, path: localDst.path)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.transfers.enqueue(source: sourcePath, destination: dstPath, sizeHint: nil) { job, progress in
                        try await srcProvider.downloadToLocal(sourcePath, toLocalURL: localDst, progress: progress, cancel: job.cancel)
                    }
                }
                return true
            default:
                return false
            }
        }

        // --- Local source: .fileURL ---
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }

        switch provider.identifier {
        case .local:
            // Existing local→local move
            var moved: [(URL, URL)] = []
            for src in urls {
                let dest = URL(fileURLWithPath: targetPath.path).appendingPathComponent(src.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) { NSSound.beep(); continue }
                do {
                    try FileManager.default.moveItem(at: src, to: dest)
                    moved.append((src, dest))
                } catch { NSSound.beep() }
            }
            if !moved.isEmpty {
                registerMoveUndo(moved)
                onMoved()
                return true
            }
            return false

        case .ssh:
            // Local→remote: upload
            let count = urls.count
            Task { @MainActor [weak self] in
                guard let self else { return }
                for src in urls {
                    let dstPath = targetPath.appending(src.lastPathComponent)
                    let size = (try? FileManager.default.attributesOfItem(atPath: src.path))?[.size] as? Int64
                    self.transfers.enqueue(source: FSPath(provider: .local, path: src.path),
                                          destination: dstPath,
                                          sizeHint: size) { [weak self] job, progress in
                        guard let self else { return }
                        try await self.provider.uploadFromLocal(src, to: dstPath, progress: progress, cancel: job.cancel)
                    }
                }
            }
            return count > 0
        }
    }

    /// Push "move dest back to src" onto the undo stack for each successful
    /// move in a drop. Symmetric — redo re-applies the move.
    fileprivate func registerMoveUndo(_ pairs: [(URL, URL)]) {
        guard let undoManager else { return }
        let onMoved = self.onMoved
        let target = self
        undoManager.registerUndo(withTarget: target) { _ in
            for (src, dest) in pairs {
                try? FileManager.default.moveItem(at: dest, to: src)
            }
            onMoved()
            undoManager.registerUndo(withTarget: target) { coord in
                coord.replayMove(pairs)
            }
        }
        undoManager.setActionName(pairs.count == 1 ? "Move" : "Move \(pairs.count) Items")
    }

    fileprivate func replayMove(_ pairs: [(URL, URL)]) {
        var done: [(URL, URL)] = []
        for (src, dest) in pairs {
            if (try? FileManager.default.moveItem(at: src, to: dest)) != nil {
                done.append((src, dest))
            }
        }
        if !done.isEmpty {
            registerMoveUndo(done)
            onMoved()
        }
    }
}
