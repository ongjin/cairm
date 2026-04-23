import SwiftUI
import AppKit

/// SwiftUI adapter for the AppKit-based file list. Hosts an NSScrollView whose
/// document view is `FileListNSTableView` (3 columns, header sort, multi-select).
///
/// Two-way data flow:
///   - SwiftUI → NSTableView: `updateNSView` reapplies the model snapshot.
///   - NSTableView → SwiftUI: Coordinator pushes selection / sortDescriptor
///     changes back into FolderModel, which re-publishes via @Observable.
struct FileListView: NSViewRepresentable {
    /// External entries source. ContentView passes either
    /// `FolderModel.sortedEntries` (normal view) or `SearchModel.results`
    /// (search active). Per-frame computed; the Coordinator snapshots it
    /// inside `applyModelSnapshot`.
    let entries: [FileEntry]
    /// Still needed so the Coordinator can read `sortDescriptor`, `selection`,
    /// and push back sort / selection changes. Read-only here — all writes go
    /// through the Coordinator's existing `folder.setSortDescriptor` / `setSelection`
    /// paths. Converting to `let` (was `@Bindable`) matches the actual usage.
    let folder: FolderModel
    /// When true, the NSTableView shows an extra "Folder" column (subtree search
    /// results need the relative path to disambiguate same-named files). Task 12
    /// wires the dynamic column logic in FileListCoordinator.
    let folderColumnVisible: Bool
    /// Root URL the Folder column truncates paths against. Nil when not in
    /// subtree search.
    let searchRoot: URL?
    /// Tab's current folder — used by the Git column to compute each entry's
    /// path relative to the repo root. Independent of `searchRoot` (which is
    /// nil outside subtree search). Nil means no git-relative mapping.
    let folderRoot: URL?
    /// Latest GitService snapshot for the tab's folder. Nil when the folder
    /// isn't a git repo; the Git column renders "—" in that case.
    let gitSnapshot: GitService.Snapshot?
    /// When false the Git column is hidden entirely. Controlled via Settings.
    let showGitColumn: Bool

    /// Called when a row is activated (double-click or ⏎). The closure receives
    /// the FileEntry; the caller decides whether to push history or open in NSWorkspace.
    let onActivate: (FileEntry) -> Void
    /// Called when the user picks "Add to Pinned" from the row context menu (folders only).
    let onAddToPinned: (FileEntry) -> Void
    /// Predicate used to label the menu item "Unpin" vs "Add to Pinned".
    let isPinnedCheck: (FileEntry) -> Bool
    let onSelectionChanged: (FileEntry?) -> Void
    /// Called after a drop-move successfully relocates files. The host should
    /// reload the folder so the moved entries disappear from this list.
    var onMoved: () -> Void = {}
    /// Tab-scoped undo stack. The coordinator registers inverse FS ops on
    /// it after every successful move / trash so ⌘Z works.
    var undoManager: UndoManager? = nil
    /// Active file-system provider for the tab. Routes rename/delete/mkdir
    /// through the correct backend (local vs. SSH).
    let provider: FileSystemProvider
    /// Transfer controller for cross-provider drag-drop (upload / download).
    let transfers: TransferController

    private static func makeGitColumn() -> NSTableColumn {
        let col = NSTableColumn(identifier: .git)
        col.title = "Git"
        col.minWidth = 28
        col.width = 40
        return col
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false   // Glass 투과

        let table = FileListNSTableView()
        // Glass Blue 배경이 투과되도록 opaque 끄기. alt row 색상은 투명 위에서
        // 읽기 어려우므로 비활성화.
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.style = .inset
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        // 3 columns: name (with icon), size, modified.
        let nameCol = NSTableColumn(identifier: .name)
        nameCol.title = "Name"
        nameCol.minWidth = 180
        nameCol.width = 320
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        table.addTableColumn(nameCol)

        let sizeCol = NSTableColumn(identifier: .size)
        sizeCol.title = "Size"
        sizeCol.minWidth = 70
        sizeCol.width = 90
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        table.addTableColumn(sizeCol)

        let modCol = NSTableColumn(identifier: .modified)
        modCol.title = "Modified"
        modCol.minWidth = 140
        modCol.width = 180
        modCol.sortDescriptorPrototype = NSSortDescriptor(key: "modified", ascending: false)
        table.addTableColumn(modCol)

        // Git column — only when the folder is actually a repo AND the
        // setting is on. An always-empty column is just visual noise outside
        // a git working tree, so we hide it rather than render "—" everywhere.
        if showGitColumn && gitSnapshot != nil {
            table.addTableColumn(Self.makeGitColumn())
        }

        // Drag & drop: export selected rows as file URLs (local) or FSPath
        // payloads (remote) and accept incoming drops on folder rows.
        table.registerForDraggedTypes([.fileURL, .cairnFSPath])
        table.setDraggingSourceOperationMask([.move, .copy], forLocal: false)
        table.setDraggingSourceOperationMask(.move, forLocal: true)

        // Coordinator wears both hats.
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        // Double-click activation. Coordinator handles ⏎ via the subclass's keyDown.
        table.target = context.coordinator
        table.doubleAction = #selector(FileListCoordinator.handleDoubleClick(_:))

        // Initial sort indicator on Name column.
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        // Enter kicks off inline rename (Finder parity). Opening a file/folder
        // stays on double-click + ⌘↓.
        table.renameHandler = { [weak coord = context.coordinator] in
            coord?.renameSelected()
        }
        table.deleteHandler = { [weak coord = context.coordinator] in
            coord?.deleteSelected()
        }
        table.copyHandler = { [weak coord = context.coordinator] in
            coord?.copySelectedToClipboard()
        }
        table.pasteHandler = { [weak coord = context.coordinator] op in
            coord?.pasteFromClipboard(operation: op)
        }

        // Right-click menu — delegate to Coordinator.
        table.menuHandler = { [weak coord = context.coordinator] event in
            coord?.menu(for: event)
        }

        // Quick Look (Space): route panel queries to the Coordinator.
        table.quickLookDelegate = context.coordinator

        context.coordinator.attach(table: table)
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? FileListNSTableView else { return }
        context.coordinator.updateBindings(
            folder: folder,
            provider: provider,
            transfers: transfers,
            onActivate: onActivate,
            onAddToPinned: onAddToPinned,
            isPinnedCheck: isPinnedCheck,
            onSelectionChanged: onSelectionChanged,
            onMoved: onMoved,
            undoManager: undoManager
        )
        // Sync Git column presence with the current setting AND whether
        // the active folder is a git repo. Re-evaluated on every update so
        // navigating into / out of a repo adds / removes the column live.
        let shouldShowGit = showGitColumn && gitSnapshot != nil
        let hasGit = table.tableColumn(withIdentifier: .git) != nil
        if shouldShowGit && !hasGit {
            table.addTableColumn(Self.makeGitColumn())
        } else if !shouldShowGit && hasGit, let col = table.tableColumn(withIdentifier: .git) {
            table.removeTableColumn(col)
        }
        context.coordinator.setEntries(entries, searchRoot: searchRoot)
        context.coordinator.setFolderColumnVisible(folderColumnVisible)
        context.coordinator.setFolderRoot(folderRoot)
        context.coordinator.setGitSnapshot(gitSnapshot)
        context.coordinator.applyModelSnapshot(table: table)
    }

    func makeCoordinator() -> FileListCoordinator {
        FileListCoordinator(folder: folder,
                            provider: provider,
                            transfers: transfers,
                            onActivate: onActivate,
                            onAddToPinned: onAddToPinned,
                            isPinnedCheck: isPinnedCheck,
                            onSelectionChanged: onSelectionChanged,
                            onMoved: onMoved,
                            undoManager: undoManager)
    }
}

extension NSUserInterfaceItemIdentifier {
    static let name = NSUserInterfaceItemIdentifier("col.name")
    static let size = NSUserInterfaceItemIdentifier("col.size")
    static let modified = NSUserInterfaceItemIdentifier("col.modified")
    static let folder = NSUserInterfaceItemIdentifier("col.folder")
    static let git = NSUserInterfaceItemIdentifier("col.git")
}
