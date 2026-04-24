import XCTest
@testable import Cairn

final class TabTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Tab.disableBackgroundServicesForTests = true
    }

    override func tearDown() {
        Tab.disableBackgroundServicesForTests = false
        super.tearDown()
    }

    /// IndexService indexes the entire subtree synchronously on init, so we
    /// steer Tab at isolated temp directories rather than `/tmp` or `/usr`
    /// (which would pull millions of files through the indexer).
    private func tmp() -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("TabTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func makeTab(initial: URL) -> Tab {
        let bookmarks = BookmarkStore(storageDirectory: tmp())
        return Tab(engine: CairnEngine(), bookmarks: bookmarks, initialURL: initial)
    }

    private func mkEntry(_ name: String) -> FileEntry {
        FileEntry(
            path: RustString("/tmp/\(name)"),
            name: RustString(name),
            size: 0,
            modified_unix: 0,
            kind: .Regular,
            is_hidden: false,
            icon_kind: .GenericFile
        )
    }

    func test_initial_url_is_in_history() {
        let d = tmp()
        defer { try? FileManager.default.removeItem(at: d) }
        let t = makeTab(initial: d)
        XCTAssertEqual(t.currentFolder?.standardizedFileURL.path, d.standardizedFileURL.path)
    }

    func test_navigate_pushes_history() {
        let a = tmp(); let b = tmp()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let t = makeTab(initial: a)
        t.navigate(to: b)
        XCTAssertEqual(t.currentFolder?.standardizedFileURL.path, b.standardizedFileURL.path)
    }

    func test_goBack_returns_previous_url() {
        let a = tmp(); let b = tmp()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let t = makeTab(initial: a)
        t.navigate(to: b)
        XCTAssertEqual(t.goBack()?.standardizedFileURL.path, a.standardizedFileURL.path)
    }

    func test_navigate_clearsSearchState() {
        let a = tmp(); let b = tmp()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let t = makeTab(initial: a)
        t.search.query = "needle"
        t.search.scope = .folder
        t.search.refresh(
            root: t.currentPath,
            provider: t.provider,
            showHidden: false,
            sort: .init(field: .name, order: .ascending),
            folderEntries: [mkEntry("needle.txt")]
        )
        XCTAssertEqual(t.search.hitCount, 1)

        t.navigate(to: b)

        XCTAssertEqual(t.search.query, "")
        XCTAssertEqual(t.search.phase, .idle)
        XCTAssertTrue(t.search.results.isEmpty)
        XCTAssertEqual(t.search.hitCount, 0)
    }
}
