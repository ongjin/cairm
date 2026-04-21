import AppKit
import SwiftUI
import QuickLookUI

/// `representedObject` can only hold a single value, so wrap `(fileURL, appURL)`
/// as an NSObject so the target-action path can recover both when the user
/// clicks an app inside the "Open With" submenu.
final class OpenWithPayload: NSObject {
    let fileURL: URL
    let appURL: URL
    init(fileURL: URL, appURL: URL) {
        self.fileURL = fileURL
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
    private let folder: FolderModel
    private let onActivate: (FileEntry) -> Void

    private weak var table: FileListNSTableView?
    private var lastSnapshot: [FileEntry] = []
    private var isApplyingModelUpdate = false

    private var externalEntries: [FileEntry]?
    private(set) var searchRoot: URL?
    private(set) var folderColumnVisible: Bool = false

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

    private let onAddToPinned: (FileEntry) -> Void
    private let isPinnedCheck: (FileEntry) -> Bool
    private let onSelectionChanged: (FileEntry?) -> Void

    init(folder: FolderModel,
         onActivate: @escaping (FileEntry) -> Void,
         onAddToPinned: @escaping (FileEntry) -> Void,
         isPinnedCheck: @escaping (FileEntry) -> Bool,
         onSelectionChanged: @escaping (FileEntry?) -> Void) {
        self.folder = folder
        self.onActivate = onActivate
        self.onAddToPinned = onAddToPinned
        self.isPinnedCheck = isPinnedCheck
        self.onSelectionChanged = onSelectionChanged
        super.init()
    }

    func attach(table: FileListNSTableView) {
        self.table = table
        // Initial snapshot.
        applyModelSnapshot(table: table)
    }

    // MARK: - Entries injection (called by FileListView.updateNSView)

    /// Replaces the default `folder.sortedEntries` with an externally-managed
    /// entries array. Pass `nil` would keep the default; to restore the default,
    /// pass `folder.sortedEntries` explicitly from the caller.
    func setEntries(_ entries: [FileEntry], searchRoot: URL?) {
        self.externalEntries = entries
        self.searchRoot = searchRoot
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
            cell.imageView?.contentTintColor = entry.kind == .Directory ? .systemBlue : .secondaryLabelColor
            cell.textField?.stringValue = entry.name.toString()
            cell.textField?.alignment = .left
        case .size:
            cell.textField?.stringValue = entry.kind == .Directory
                ? "—"
                : byteFormatter.string(fromByteCount: Int64(entry.size))
            cell.textField?.alignment = .right
        case .modified:
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
        default:
            cell.textField?.stringValue = ""
        }
        return cell
    }

    // MARK: - Sort

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
        guard row >= 0, row < lastSnapshot.count else { return nil }
        let entry = lastSnapshot[row]

        let menu = NSMenu()

        if entry.kind == .Directory {
            let item = NSMenuItem(
                title: isPinnedCheck(entry) ? "Unpin" : "Add to Pinned",
                action: #selector(menuAddToPinned(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = entry
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let reveal = NSMenuItem(title: "Reveal in Finder",
                                action: #selector(menuRevealInFinder(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = entry
        menu.addItem(reveal)

        // Copy Path (⌥⌘C) — stays just below Reveal so the two OS-level ops sit together.
        let copyPath = NSMenuItem(title: "Copy Path",
                                  action: #selector(menuCopyPath(_:)),
                                  keyEquivalent: "c")
        copyPath.keyEquivalentModifierMask = [.command, .option]
        copyPath.target = self
        copyPath.representedObject = entry
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
        trash.representedObject = entry
        menu.addItem(trash)

        return menu
    }

    private func buildOpenWithSubmenu(for entry: FileEntry) -> NSMenu? {
        let fileURL = URL(fileURLWithPath: entry.path.toString())
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        guard !appURLs.isEmpty else { return nil }

        let submenu = NSMenu()
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: fileURL)

        // Put default app first (bold via attributedTitle), then the rest.
        var ordered: [URL] = []
        if let def = defaultApp {
            ordered.append(def)
            ordered.append(contentsOf: appURLs.filter { $0 != def })
        } else {
            ordered = appURLs
        }

        for appURL in ordered {
            let name = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            let title = (appURL == defaultApp) ? "\(name) (default)" : name
            let item = NSMenuItem(title: title,
                                  action: #selector(menuOpenWith(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = OpenWithPayload(fileURL: fileURL, appURL: appURL)
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func menuAddToPinned(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        onAddToPinned(entry)
    }

    @objc private func menuRevealInFinder(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        NSWorkspace.shared.selectFile(entry.path.toString(),
                                      inFileViewerRootedAtPath: "")
    }

    @objc private func menuCopyPath(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        let path = entry.path.toString()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
    }

    @objc private func menuMoveToTrash(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        let url = URL(fileURLWithPath: entry.path.toString())
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSLog("cairn: Move to Trash failed — \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    @objc private func menuOpenWith(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? OpenWithPayload else { return }
        NSWorkspace.shared.open([payload.fileURL],
                                withApplicationAt: payload.appURL,
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
        let symbolName: String
        if entry.kind == .Directory {
            symbolName = "folder.fill"
        } else if entry.kind == .Symlink {
            symbolName = "arrow.up.right.square"
        } else {
            symbolName = "doc"
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
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
}
