import XCTest
@testable import Cairn

final class WindowSceneModelTests: XCTestCase {
    /// IndexService indexes the entire subtree synchronously on init, so we
    /// steer Tab at isolated temp directories rather than `/tmp` directly.
    private func tmp() -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowSceneModelTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func makeScene() -> WindowSceneModel {
        let bookmarks = BookmarkStore(storageDirectory: tmp())
        return WindowSceneModel(
            engine: CairnEngine(),
            bookmarks: bookmarks,
            initialURL: tmp()
        )
    }

    func test_initial_has_one_tab() {
        let m = makeScene()
        XCTAssertEqual(m.tabs.count, 1)
        XCTAssertNotNil(m.activeTab)
    }

    func test_newTab_appends_and_activates() {
        let m = makeScene()
        m.newTab()
        XCTAssertEqual(m.tabs.count, 2)
        XCTAssertEqual(m.activeTabID, m.tabs[1].id)
    }

    func test_closeTab_picks_remaining_tab() {
        let m = makeScene()
        m.newTab()
        let closedID = m.tabs[1].id
        m.closeTab(closedID)
        XCTAssertEqual(m.tabs.count, 1)
        XCTAssertNotNil(m.activeTabID)
        XCTAssertNotEqual(m.activeTabID, closedID)
    }

    func test_activatePrevious_wraps() {
        let m = makeScene()
        m.newTab()
        m.activateTab(at: 0)
        m.activatePrevious()
        XCTAssertEqual(m.activeTabID, m.tabs[1].id)
    }
}
