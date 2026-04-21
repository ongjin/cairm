import AppKit
import SwiftUI
import QuickLookUI

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

    init(folder: FolderModel,
         onActivate: @escaping (FileEntry) -> Void,
         onAddToPinned: @escaping (FileEntry) -> Void,
         isPinnedCheck: @escaping (FileEntry) -> Bool) {
        self.folder = folder
        self.onActivate = onActivate
        self.onAddToPinned = onAddToPinned
        self.isPinnedCheck = isPinnedCheck
        super.init()
    }

    func attach(table: FileListNSTableView) {
        self.table = table
        // Initial snapshot.
        applyModelSnapshot(table: table)
    }

    // MARK: - Snapshot application (called from updateNSView)

    /// Pulls the latest sortedEntries into NSTableView and re-applies the
    /// selection set, suppressing the delegate's selection-change callback.
    func applyModelSnapshot(table: NSTableView) {
        isApplyingModelUpdate = true
        defer { isApplyingModelUpdate = false }

        lastSnapshot = folder.sortedEntries
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
        let paths = table.selectedRowIndexes.compactMap { row -> String? in
            guard row < lastSnapshot.count else { return nil }
            return lastSnapshot[row].path.toString()
        }
        folder.setSelection(Set(paths))
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

        return menu
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

    // MARK: - Quick Look

    /// Snapshot of the paths currently selected at the moment QL took control.
    /// Captured in begin to avoid races with live selection changes while the
    /// panel is up.
    private var quickLookURLs: [URL] {
        let selectedRows = table?.selectedRowIndexes ?? IndexSet()
        let paths: [URL] = selectedRows.compactMap { row in
            guard row < lastSnapshot.count else { return nil }
            let p = lastSnapshot[row].path.toString()
            return URL(fileURLWithPath: p)
        }
        // Fallback: if nothing is selected but the user pressed Space, preview
        // the clicked / first row.
        if paths.isEmpty, !lastSnapshot.isEmpty {
            let p = lastSnapshot[0].path.toString()
            return [URL(fileURLWithPath: p)]
        }
        return paths
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let urls = quickLookURLs
        guard index >= 0, index < urls.count else { return nil }
        return urls[index] as NSURL
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
