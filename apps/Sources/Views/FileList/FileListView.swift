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
    @Bindable var folder: FolderModel
    /// Called when a row is activated (double-click or ⏎). The closure receives
    /// the FileEntry; the caller decides whether to push history or open in NSWorkspace.
    let onActivate: (FileEntry) -> Void
    /// Called when the user picks "Add to Pinned" from the row context menu (folders only).
    let onAddToPinned: (FileEntry) -> Void
    /// Predicate used to label the menu item "Unpin" vs "Add to Pinned".
    let isPinnedCheck: (FileEntry) -> Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let table = FileListNSTableView()
        table.usesAlternatingRowBackgroundColors = true
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

        // Coordinator wears both hats.
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        // Double-click activation. Coordinator handles ⏎ via the subclass's keyDown.
        table.target = context.coordinator
        table.doubleAction = #selector(FileListCoordinator.handleDoubleClick(_:))

        // Initial sort indicator on Name column.
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        // Subclass needs a back-pointer for ⏎ activation.
        table.activationHandler = { [weak coord = context.coordinator] in
            coord?.activateSelected()
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
        context.coordinator.applyModelSnapshot(table: table)
    }

    func makeCoordinator() -> FileListCoordinator {
        FileListCoordinator(folder: folder,
                            onActivate: onActivate,
                            onAddToPinned: onAddToPinned,
                            isPinnedCheck: isPinnedCheck)
    }
}

extension NSUserInterfaceItemIdentifier {
    static let name = NSUserInterfaceItemIdentifier("col.name")
    static let size = NSUserInterfaceItemIdentifier("col.size")
    static let modified = NSUserInterfaceItemIdentifier("col.modified")
}
