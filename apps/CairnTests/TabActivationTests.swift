import XCTest
@testable import Cairn

@MainActor
final class TabActivationTests: XCTestCase {
    func test_setActive_flagTogglesIsActive() {
        let engine = try! CairnEngine()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BookmarkStore(storageDirectory: tmp)
        let tab = Tab(engine: engine, bookmarks: store, initialURL: tmp)

        XCTAssertTrue(tab.isActive, "new tab should start active")
        tab.setActive(false)
        XCTAssertFalse(tab.isActive)
        tab.setActive(true)
        XCTAssertTrue(tab.isActive)
    }
}
