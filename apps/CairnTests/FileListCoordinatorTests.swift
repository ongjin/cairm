import XCTest
@testable import Cairn
import AppKit

@MainActor
final class FileListCoordinatorTests: XCTestCase {
    private func mkDir(_ name: String) -> FileEntry {
        FileEntry(
            path: RustString("/tmp/\(name)"),
            name: RustString(name),
            size: 0,
            modified_unix: 0,
            kind: .Directory,
            is_hidden: false,
            icon_kind: .Folder
        )
    }

    func test_updateBindings_swapsActivateClosure() {
        let engine = CairnEngine()
        let folderA = FolderModel(engine: engine)
        let folderB = FolderModel(engine: engine)
        let entry = mkDir("Documents")
        folderA.setEntries([entry])
        folderB.setEntries([entry])

        var aActivated = 0
        var bActivated = 0

        let coord = FileListCoordinator(
            folder: folderA,
            provider: LocalFileSystemProvider(engine: CairnEngine()),
            transfers: TransferController(),
            onActivate: { _ in aActivated += 1 },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )

        coord.fireActivate(entry: entry)
        XCTAssertEqual(aActivated, 1)
        XCTAssertEqual(bActivated, 0)

        coord.updateBindings(
            folder: folderB,
            provider: LocalFileSystemProvider(engine: CairnEngine()),
            transfers: TransferController(),
            onActivate: { _ in bActivated += 1 },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )

        coord.fireActivate(entry: entry)
        XCTAssertEqual(aActivated, 1, "A must NOT fire again after updateBindings")
        XCTAssertEqual(bActivated, 1, "B must now fire after updateBindings")
    }

    func test_updateBindings_swapsFolderReference() {
        let engine = CairnEngine()
        let folderA = FolderModel(engine: engine)
        let folderB = FolderModel(engine: engine)

        let provider = LocalFileSystemProvider(engine: engine)
        let coord = FileListCoordinator(
            folder: folderA,
            provider: provider,
            transfers: TransferController(),
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )
        XCTAssertTrue(coord.folderRefForTest === folderA)

        coord.updateBindings(
            folder: folderB,
            provider: provider,
            transfers: TransferController(),
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )
        XCTAssertTrue(coord.folderRefForTest === folderB)
    }

    func test_setFolderColumnVisible_adds_and_removes_column() {
        let engine2 = CairnEngine()
        let folder = FolderModel(engine: engine2)
        let coord = FileListCoordinator(
            folder: folder,
            provider: LocalFileSystemProvider(engine: engine2),
            transfers: TransferController(),
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false },
            onSelectionChanged: { _ in }
        )
        let table = FileListNSTableView()
        // Seed the usual 3 columns so moveColumn works during the add path.
        for id in ["name", "size", "modified"] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col.\(id)"))
            c.title = id.capitalized
            table.addTableColumn(c)
        }
        coord.attach(table: table)

        XCTAssertEqual(table.tableColumns.count, 3)
        coord.setFolderColumnVisible(true)
        XCTAssertEqual(table.tableColumns.count, 4)
        XCTAssertTrue(table.tableColumns.contains { $0.identifier == .folder })

        coord.setFolderColumnVisible(false)
        XCTAssertEqual(table.tableColumns.count, 3)
        XCTAssertFalse(table.tableColumns.contains { $0.identifier == .folder })
    }
}
