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
                                 QLPreviewPanelDataSource,
                                 QLPreviewPanelDelegate {
    private var folder: FolderModel
    private var onActivate: (FileEntry) -> Void

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

    init(folder: FolderModel,
         onActivate: @escaping (FileEntry) -> Void,
         onAddToPinned: @escaping (FileEntry) -> Void,
         isPinnedCheck: @escaping (FileEntry) -> Bool,
         onSelectionChanged: @escaping (FileEntry?) -> Void,
         onMoved: @escaping () -> Void = {},
         undoManager: UndoManager? = nil) {
        self.folder = folder
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
                        onActivate: @escaping (FileEntry) -> Void,
                        onAddToPinned: @escaping (FileEntry) -> Void,
                        isPinnedCheck: @escaping (FileEntry) -> Bool,
                        onSelectionChanged: @escaping (FileEntry?) -> Void,
                        onMoved: @escaping () -> Void = {},
                        undoManager: UndoManager? = nil) {
        let folderChanged = self.folder !== folder
        self.folder = folder
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
            if let snap = gitSnapshot {
                if snap.modifiedPaths.contains(rel) {
                    symbol = "M"; color = .systemYellow
                } else if snap.addedPaths.contains(rel) {
                    symbol = "A"; color = .systemGreen
                } else if snap.deletedPaths.contains(rel) {
                    symbol = "D"; color = .systemRed
                } else if snap.untrackedPaths.contains(rel) {
                    symbol = "??"; color = .secondaryLabelColor
                } else {
                    symbol = "—"; color = .tertiaryLabelColor
                }
            } else {
                symbol = "—"; color = .tertiaryLabelColor
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

    /// Called by FileListNSTableView's keyDown when ⏎ / Enter is pressed.
    /// When multiple rows are selected, AppKit's `selectedRow` returns the
    /// focused row only — we activate just that one. Phase 2 may add a
    /// bulk-activation path (open all selected in their default apps).
    func activateSelected() {
        guard let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, row < lastSnapshot.count else { return }
        onActivate(lastSnapshot[row])
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

    /// Right-click on empty space: expose Paste / Paste Item Here when the
    /// pasteboard has content. Both items use standard Cocoa selectors so the
    /// responder chain routes them through FileListNSTableView's overrides.
    /// Returns nil when there's nothing to paste — no menu appears at all.
    private func emptySpaceMenu() -> NSMenu? {
        let pasted = ClipboardPasteService.read(from: .general)
        guard pasted != nil else { return nil }

        let menu = NSMenu()

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

        return menu
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
    /// row; partial failures still trigger a reload so the successful
    /// removals are reflected immediately.
    func deleteSelected() {
        guard let table = self.table else { return }
        let indexes = table.selectedRowIndexes
        guard !indexes.isEmpty else { return }
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
        let fileURL = URL(fileURLWithPath: payload.entry.path.toString())
        NSWorkspace.shared.open([fileURL],
                                withApplicationAt: appURL,
                                configuration: .init()) { _, error in
            if let error { NSLog("cairn: Open With failed — \(error.localizedDescription)") }
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
        let paths: [URL] = selectedRows.compactMap { row in
            guard row < lastSnapshot.count else { return nil }
            return URL(fileURLWithPath: lastSnapshot[row].path.toString())
        }
        if paths.isEmpty, !lastSnapshot.isEmpty {
            quickLookSnapshot = [URL(fileURLWithPath: lastSnapshot[0].path.toString())]
        } else {
            quickLookSnapshot = paths
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

        let textField = NSTextField(labelWithString: "")
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
        let urls = indexes.compactMap { idx -> URL? in
            guard idx >= 0, idx < lastSnapshot.count else { return nil }
            return URL(fileURLWithPath: lastSnapshot[idx].path.toString())
        }
        guard !urls.isEmpty else { return }
        ClipboardPasteService.writeFileURLs(urls, to: .general)
    }

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
        case (.files(let urls), .move):
            pasteMove(urls: urls, into: dir)
        case (.image(let data, let ext), _):
            // Operation is ignored for images — clipboard images don't have a
            // source file to move. ⌘V and ⌥⌘V both "paste" the image.
            pasteImage(data: data, ext: ext, into: dir)
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
// Drag source: any selected row exports its absolute file URL via the standard
// `.fileURL` pasteboard type, so files can be dragged out to Finder or any
// other URL-aware target.
//
// Drop target: when the proposed drop is .on a folder row, accept the drop
// and `FileManager.moveItem` each pasteboard URL into that folder. We don't
// accept `.above` drops on a list — reordering files in a folder isn't a
// meaningful operation; if the user wants to move INTO the current folder
// they should drop on the breadcrumb / sidebar instead.
extension FileListCoordinator {
    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < lastSnapshot.count else { return nil }
        let entry = lastSnapshot[row]
        return URL(fileURLWithPath: entry.path.toString()) as NSURL
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard op == .on,
              row >= 0, row < lastSnapshot.count,
              lastSnapshot[row].kind == .Directory else {
            return []
        }
        let targetURL = URL(fileURLWithPath: lastSnapshot[row].path.toString())
        // Block dropping a folder onto itself or one of its descendants.
        if let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for src in urls {
                if src.standardizedFileURL.path == targetURL.standardizedFileURL.path { return [] }
                if targetURL.standardizedFileURL.path.hasPrefix(src.standardizedFileURL.path + "/") { return [] }
            }
        }
        return .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation op: NSTableView.DropOperation) -> Bool {
        guard op == .on, row >= 0, row < lastSnapshot.count else { return false }
        let target = lastSnapshot[row]
        guard target.kind == .Directory else { return false }
        let targetURL = URL(fileURLWithPath: target.path.toString())

        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }

        var moved: [(URL, URL)] = []
        for src in urls {
            let dest = targetURL.appendingPathComponent(src.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                NSSound.beep()
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
            registerMoveUndo(moved)
            onMoved()
            return true
        }
        return false
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
