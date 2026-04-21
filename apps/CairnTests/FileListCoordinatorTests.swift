import XCTest
@testable import Cairn
import AppKit

final class FileListCoordinatorTests: XCTestCase {
    func test_setFolderColumnVisible_adds_and_removes_column() {
        let folder = FolderModel(engine: CairnEngine())
        let coord = FileListCoordinator(
            folder: folder,
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
