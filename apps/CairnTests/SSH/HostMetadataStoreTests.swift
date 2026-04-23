import XCTest
@testable import Cairn

final class HostMetadataStoreTests: XCTestCase {
    func testRoundTrip() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = HostMetadataStore(url: tmp)
        store.update("prod-api") { $0.pinned = true; $0.lastConnectedAt = Date(timeIntervalSince1970: 0) }
        let reloaded = HostMetadataStore(url: tmp)
        XCTAssertTrue(reloaded.metadata(for: "prod-api").pinned)
    }

    func testDefaultEmpty() {
        let store = HostMetadataStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        XCTAssertFalse(store.metadata(for: "unknown").pinned)
        XCTAssertNil(store.metadata(for: "unknown").lastConnectedAt)
    }
}
