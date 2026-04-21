import XCTest
@testable import Cairn

final class BookmarkStoreTests: XCTestCase {
    var tempDir: URL!
    var store: BookmarkStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = BookmarkStore(storageDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_register_pinned_adds_entry() throws {
        // Use tempDir itself as a "real" folder we definitely can resolve.
        let entry = try store.register(tempDir, kind: .pinned)
        XCTAssertFalse(store.pinned.isEmpty)
        XCTAssertEqual(store.pinned.first?.id, entry.id)
        XCTAssertTrue(entry.lastKnownPath.hasSuffix(tempDir.lastPathComponent))
    }

    func test_persistence_round_trip() throws {
        _ = try store.register(tempDir, kind: .pinned)

        // Re-create store — simulating app restart.
        let reborn = BookmarkStore(storageDirectory: tempDir)
        XCTAssertEqual(reborn.pinned.count, 1)
        XCTAssertEqual(reborn.pinned.first?.lastKnownPath, tempDir.standardizedFileURL.path)
    }

    func test_recent_lru_caps_at_20() throws {
        // Fake bookmark data via registerRaw — registering 21 distinct paths.
        for i in 0..<21 {
            let child = tempDir.appendingPathComponent("child-\(i)")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            _ = try store.register(child, kind: .recent)
        }
        XCTAssertEqual(store.recent.count, 20, "Recent should cap at 20")
    }

    func test_recent_dedup_moves_to_front() throws {
        let a = tempDir.appendingPathComponent("a")
        let b = tempDir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)

        _ = try store.register(a, kind: .recent)
        _ = try store.register(b, kind: .recent)
        XCTAssertEqual(store.recent.first?.lastKnownPath, b.standardizedFileURL.path)

        // Re-register a → should jump to front.
        _ = try store.register(a, kind: .recent)
        XCTAssertEqual(store.recent.first?.lastKnownPath, a.standardizedFileURL.path)
        XCTAssertEqual(store.recent.count, 2)
    }
}
