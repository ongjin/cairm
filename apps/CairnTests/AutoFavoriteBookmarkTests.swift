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

    // MARK: - autoFavoriteRequiresPicker classification

    func test_requiresPicker_applicationsIsDirect() {
        XCTAssertFalse(AppModel.autoFavoriteRequiresPicker(URL(fileURLWithPath: "/Applications")))
        XCTAssertFalse(AppModel.autoFavoriteRequiresPicker(URL(fileURLWithPath: "/Applications/Safari.app")))
    }

    func test_requiresPicker_downloadsIsDirect() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertFalse(AppModel.autoFavoriteRequiresPicker(home.appendingPathComponent("Downloads")))
        XCTAssertFalse(AppModel.autoFavoriteRequiresPicker(home.appendingPathComponent("Downloads/nested/thing.txt")))
    }

    func test_requiresPicker_desktopAndDocumentsRequirePanel() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertTrue(AppModel.autoFavoriteRequiresPicker(home.appendingPathComponent("Desktop")))
        XCTAssertTrue(AppModel.autoFavoriteRequiresPicker(home.appendingPathComponent("Documents")))
    }

    func test_requiresPicker_homeAndMediaFoldersRequirePanel() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertTrue(AppModel.autoFavoriteRequiresPicker(home))
        XCTAssertTrue(AppModel.autoFavoriteRequiresPicker(home.appendingPathComponent("Music")))
        XCTAssertTrue(AppModel.autoFavoriteRequiresPicker(home.appendingPathComponent("Pictures")))
        XCTAssertTrue(AppModel.autoFavoriteRequiresPicker(home.appendingPathComponent("Movies")))
    }

    func test_requiresPicker_handlesPathStandardization() {
        // `/Applications/./Safari.app` should still classify as direct.
        let dotted = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(".")
            .appendingPathComponent("Safari.app")
        XCTAssertFalse(AppModel.autoFavoriteRequiresPicker(dotted))
    }
}
