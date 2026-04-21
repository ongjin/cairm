import XCTest
@testable import Cairn

final class LastFolderStoreTests: XCTestCase {
    /// Uses a fresh UserDefaults suite per test so runs don't leak into the real
    /// defaults or into each other.
    private func freshDefaults() -> UserDefaults {
        let suite = "LastFolderStoreTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_save_then_load_roundtrip() throws {
        let d = freshDefaults()
        let store = LastFolderStore(defaults: d)
        let tmp = FileManager.default.temporaryDirectory
        store.save(tmp)
        XCTAssertEqual(store.load()?.standardizedFileURL, tmp.standardizedFileURL)
    }

    func test_load_returns_nil_when_key_absent() {
        let d = freshDefaults()
        let store = LastFolderStore(defaults: d)
        XCTAssertNil(store.load())
    }

    func test_load_returns_nil_when_path_no_longer_exists() {
        let d = freshDefaults()
        let store = LastFolderStore(defaults: d)
        let ghost = URL(fileURLWithPath: "/tmp/definitely-not-there-\(UUID().uuidString)")
        store.save(ghost)
        XCTAssertNil(store.load())
    }
}
