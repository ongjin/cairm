import XCTest
@testable import Cairn

@MainActor
final class AutoFavoriteBookmarkTests: XCTestCase {
    private var tempDir: URL!
    private var store: BookmarkStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoFavoriteBookmarkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = BookmarkStore(storageDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_existingBookmark_returnedWithoutPrompt() throws {
        let target = tempDir.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let entry = try store.register(target, kind: .pinned)

        let found = AppModel.lookupExistingBookmark(for: target, in: store)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, entry.id)
    }

    func test_noBookmark_returnsNil() {
        let target = tempDir.appendingPathComponent("Documents")
        let found = AppModel.lookupExistingBookmark(for: target, in: store)
        XCTAssertNil(found)
    }

    func test_pathStandardization_matchesDotSegmentAlias() throws {
        let raw = tempDir.appendingPathComponent("standardized")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)

        let entry = try store.register(raw, kind: .pinned)

        let alias = tempDir
            .appendingPathComponent("standardized")
            .appendingPathComponent(".")
        let found = AppModel.lookupExistingBookmark(for: alias, in: store)
        XCTAssertEqual(found?.id, entry.id)
    }

}
