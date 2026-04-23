import XCTest
@testable import Cairn

final class FileSystemProviderTests: XCTestCase {
    func testLocalProviderListsTempDirectory() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "hello".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let p = LocalFileSystemProvider(engine: CairnEngine())
        let entries = try await p.list(FSPath(provider: .local, path: tmp.path))
        XCTAssertEqual(entries.count, 1)
    }

    func testFSPathParentAndAppending() {
        let root = FSPath(provider: .local, path: "/Users/cyj")
        XCTAssertEqual(root.appending("Projects").path, "/Users/cyj/Projects")
        XCTAssertEqual(root.parent()?.path, "/Users")
    }
}
