import XCTest
@testable import Cairn

final class TabTests: XCTestCase {
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
}
