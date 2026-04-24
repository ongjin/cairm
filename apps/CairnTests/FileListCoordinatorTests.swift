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

    private func mkFile(_ name: String) -> FileEntry {
        FileEntry(
            path: RustString("/tmp/\(name)"),
            name: RustString(name),
            size: 12,
            modified_unix: 0,
            kind: .Regular,
            is_hidden: false,
            icon_kind: .GenericFile
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
            isPinnedCheck: { _ in false }
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
            isPinnedCheck: { _ in false }
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
            isPinnedCheck: { _ in false }
        )
        XCTAssertTrue(coord.folderRefForTest === folderA)

        coord.updateBindings(
            folder: folderB,
            provider: provider,
            transfers: TransferController(),
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false }
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
            isPinnedCheck: { _ in false }
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

    func test_menu_showsExternalEditorForSSHRegularFilesOnly() throws {
        let engine = CairnEngine()
        let entry = mkFile("remote.txt")
        let folder = FolderModel(engine: engine)
        folder.setEntries([entry])
        let coord = FileListCoordinator(
            folder: folder,
            provider: MenuRemoteProvider(),
            transfers: TransferController(),
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false }
        )
        let table = seededTable()
        table.dataSource = coord
        table.delegate = coord
        coord.attach(table: table)

        let menu = try XCTUnwrap(coord.menu(for: rowEvent()))
        XCTAssertTrue(menu.items.map(\.title).contains("Edit in External Editor"))

        coord.updateBindings(
            folder: folder,
            provider: LocalFileSystemProvider(engine: engine),
            transfers: TransferController(),
            onActivate: { _ in },
            onAddToPinned: { _ in },
            isPinnedCheck: { _ in false }
        )
        let localMenu = try XCTUnwrap(coord.menu(for: rowEvent()))
        XCTAssertFalse(localMenu.items.map(\.title).contains("Edit in External Editor"))
    }

    private func seededTable() -> FileListNSTableView {
        let table = FileListNSTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        for id in ["name", "size", "modified"] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col.\(id)"))
            c.title = id.capitalized
            table.addTableColumn(c)
        }
        return table
    }

    private func rowEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 8, y: 8),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
    }
}

private final class MenuRemoteProvider: FileSystemProvider {
    private let target = SshTarget(user: "u", hostname: "h", port: 22, configHashHex: "menu")

    var identifier: ProviderID { .ssh(target) }
    var displayScheme: String? { "ssh://" }
    var supportsServerSideCopy: Bool { false }

    func list(_ path: FSPath) async throws -> [FileEntry] { [] }
    func stat(_ path: FSPath) async throws -> FileStat {
        FileStat(size: 0, mtime: nil, mode: 0o644, isDirectory: false)
    }
    func exists(_ path: FSPath) async throws -> Bool { false }
    func mkdir(_ path: FSPath) async throws {}
    func rename(from: FSPath, to: FSPath) async throws {}
    func delete(_ paths: [FSPath]) async throws {}
    func copyInPlace(from: FSPath, to: FSPath) async throws {}
    func readHead(_ path: FSPath, max: Int) async throws -> Data { Data() }
    func downloadToCache(_ path: FSPath) async throws -> URL { URL(fileURLWithPath: path.path) }
    func uploadFromLocal(_ localURL: URL,
                         to remotePath: FSPath,
                         progress: @escaping (Int64) -> Void,
                         cancel: CancelToken) async throws {}
    func downloadToLocal(_ remotePath: FSPath,
                         toLocalURL: URL,
                         progress: @escaping (Int64) -> Void,
                         cancel: CancelToken) async throws {}
    func realpath(_ path: String) async throws -> String { path }
}
